
# 02_deploy_azure_resources.R
# 
# This script sets up Azure resources including the Batch cluster and the blob
# container where the data will be stored. The original dataset is replicated 
# from 11 SKUs of one product to 1000 SKUs of 90 products. The docker image to be 
# deployed on each cluster node is defined and pushed to your Docker Hub account.
#
# Note: you must have logged in to your Docker Hub account and the Azure CLI.
#
# Run time ~6 minutes


# Set environment variables ----------------------------------------------------

library(dotenv)
library(jsonlite)
library(doAzureParallel)
library(AzureStor)

source("R/options.R")
source("R/utilities.R")
source("R/create_cluster_json.R")
source("R/create_credentials_json.R")

set_resource_specs()


# Create resources with Azure CLI ----------------------------------------------

# Create resource group

run("az group create --name %s --location %s --query properties.provisioningState",
    get_env("RESOURCE_GROUP"), get_env("REGION"))


# Create service principal. You can ignore any retry warnings. If you have an
# existing service principal of the same name, you can ignore the error message.

run(
  paste("az ad sp create-for-rbac",
        "--name %s --subscription %s --scopes %s"),
  paste0("https://", get_env("SERVICE_PRINCIPAL_NAME")),
  get_env("SUBSCRIPTION_ID"),
  paste0("/subscriptions/", get_env("SUBSCRIPTION_ID"),
         "/resourceGroups/", get_env("RESOURCE_GROUP"))
)


# Retrieve the app ID

set_env(
  "SERVICE_PRINCIPAL_APPID",
  run(
    "az ad sp show --id %s --query appId -o tsv",
    paste0("https://", get_env("SERVICE_PRINCIPAL_NAME")),
    intern = TRUE
  )
)


# Retrieve the service principal's credential

set_env(
  "SERVICE_PRINCIPAL_CRED",
  run("az ad sp credential reset --name %s --query password -o tsv",
      paste0("https://", get_env("SERVICE_PRINCIPAL_NAME")),
      intern = TRUE)
)


# Create storage account

run(
  paste("az storage account create",
        "--kind BlobStorage --sku Standard_LRS --access-tier Hot",
        "--name %s --resource-group %s --location %s --query provisioningState"),
  get_env("STORAGE_ACCOUNT_NAME"),
  get_env("RESOURCE_GROUP"),
  get_env("REGION")
)


# Retrieve storage account key

set_env(
  "STORAGE_ACCOUNT_KEY",
  run("az storage account keys list --account-name %s --query [0].value -o tsv",
        get_env("STORAGE_ACCOUNT_NAME"), intern = TRUE)
)


# Construct blob container URL

set_env("BLOB_CONTAINER_URL",
       paste0(
         "https://", get_env("STORAGE_ACCOUNT_NAME"),
         ".blob.core.windows.net/", get_env("BLOB_CONTAINER_NAME"), "/"
       )
)


# Create batch account

run(
  paste("az batch account create",
        "--name %s --resource-group %s --location %s --storage-account %s",
        "--query provisioningState"),
  get_env("BATCH_ACCOUNT_NAME"), get_env("RESOURCE_GROUP"),
  get_env("REGION"), get_env("STORAGE_ACCOUNT_NAME")
)


# Replicate data ---------------------------------------------------------------

# Expand data to 1000 SKUs from 90 products

lapply(2:floor(TARGET_SKUS / 11),
       function(m) {
         file.copy("data/history/product1.csv",
                   paste0("data/history/product", m, ".csv"),
                   overwrite = TRUE)
         file.copy("data/futurex/product1.csv",
                   paste0("data/futurex/product", m, ".csv"),
                   overwrite = TRUE)
       })


# Create Blob container and upload resources -----------------------------------

cont <- create_blob_container(
  get_env("BLOB_CONTAINER_URL"),
  key = get_env("STORAGE_ACCOUNT_KEY")
)

multiupload_blob(cont, src = "data/history/*", dest = "data/history")
multiupload_blob(cont, src = "data/futurex/*", dest = "data/futurex")
multiupload_blob(cont, src = "models/*", dest = "models")


# Build worker docker image ----------------------------------------------------

# The worker docker container will be deployed on each node of the Batch cluster.
# The dockerfile used to build to the worker docker image can be reviewed in
# docker/worker/dockerfile


# Build and upload the worker docker image to Docker Hub

run(
  "sudo docker build -t %s -f docker/worker/dockerfile .",
  paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE"))
)

run(
  "sudo docker tag %s:latest %s",
  paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE")),
  paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE"))
)

run("sudo docker push %s",
    paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE")))


# Define cluster ---------------------------------------------------------------

# Create json file to store doAzureParallel credentials

create_credentials_json()


# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Create the cluster config file and provision the cluster

create_cluster_json <- function(save_dir = "azure") {
  
  config <- list(
    name = get_env("CLUSTER_NAME"),
    vmSize = get_env("VM_SIZE"),
    maxTasksPerNode = 1,
    poolSize = list(
      dedicatedNodes = list(
        min = 0,
        max = as.integer(get_env("NUM_NODES"))
      ),
      lowPriorityNodes = list(
        min = 0,
        max = 0
      ),
      autoscaleFormula = "QUEUE_AND_RUNNING"
    ),
    containerImage = paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE")),
    commandLine = c()
  )
  
  config_json <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(config_json, file = file.path(save_dir, "cluster.json"))
  
}

write_function(create_cluster_json, "R/create_cluster_json.R")

create_cluster_json(save_dir = "azure")

makeCluster("azure/cluster.json")
