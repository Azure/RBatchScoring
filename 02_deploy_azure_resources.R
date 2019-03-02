
# 02_deploy_azure_resources.R
# 
# This script sets up Azure resources including the Batch cluster and the blob
# container where the data will be stored. The original dataset is replicated 
# from 11 SKUs of one product to 1000 SKUs of 90 products. The docker image to be 
# deployed on each cluster node is defined and pushed to your Docker Hub account.
#
# Note: you must have logged in to your Docker Hub account and the Azure CLI.
#
# Run time ~4 minutes


# Set environment variables ----------------------------------------------------

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

library(dotenv)
library(jsonlite)
library(doAzureParallel)
library(AzureStor)

source("R/options.R")
source("R/utilities.R")
source("R/set_environment_variables.R")
source("R/create_cluster_json.R")
source("R/create_credentials_json.R")

set_environment_variables()



# Create resources with Azure CLI ----------------------------------------------

# Create resource group

run("az group create --name %s --location %s",
    Sys.getenv("RESOURCE_GROUP"), Sys.getenv("REGION"))


# Create storage account

run(
  paste("az storage account create",
        "--kind BlobStorage --sku Standard_LRS --access-tier Hot",
        "--name %s --resource-group %s --location %s"),
  Sys.getenv("STORAGE_ACCOUNT_NAME"),
  Sys.getenv("RESOURCE_GROUP"),
  Sys.getenv("REGION")
)


# Retrieve storage account key

setenv(
  "STORAGE_ACCOUNT_KEY",
  fromJSON(
    run("az storage account keys list --account-name %s --query [0].value",
        Sys.getenv("STORAGE_ACCOUNT_NAME"), intern = TRUE)
  )
)


# Construct blob container URL

setenv("BLOB_CONTAINER_URL",
       paste0(
         "https://", Sys.getenv("STORAGE_ACCOUNT_NAME"),
         ".blob.core.windows.net/", Sys.getenv("BLOB_CONTAINER_NAME"), "/"
       )
)


# Create batch account

run(
  paste("az batch account create",
        "--name %s --resource-group %s --location %s --storage-account %s"),
  Sys.getenv("BATCH_ACCOUNT_NAME"), Sys.getenv("RESOURCE_GROUP"),
  Sys.getenv("REGION"), Sys.getenv("STORAGE_ACCOUNT_NAME")
)


# Create service principal and retrieve credentials

sp_credentials <- run(
    paste("az ad sp create-for-rbac",
          "--name %s --subscription %s --scopes %s"),
    paste0("https://", Sys.getenv("SERVICE_PRINCIPAL_NAME")),
    Sys.getenv("SUBSCRIPTION_ID"),
    paste0("/subscriptions/", Sys.getenv("SUBSCRIPTION_ID"),
            "/resourceGroups/", Sys.getenv("RESOURCE_GROUP")),
    intern = TRUE
)
sp_credentials <- fromJSON(sp_credentials)
print(sp_credentials)

setenv("SERVICE_PRINCIPAL_APPID", sp_credentials$appId)
setenv("SERVICE_PRINCIPAL_CRED", sp_credentials$password)


# Replicate data ---------------------------------------------------------------

# Factor by which to replicate products. Expand to 1000 SKUs from 90 products

multiplier <- floor(TARGET_SKUS / 11)

for (m in 2:multiplier) {
  run("cp data/history/product1.csv data/history/product%s.csv", m)
  run("cp data/futurex/product1.csv data/futurex/product%s.csv", m)
}


# Create Blob container and upload resources -----------------------------------

cont <- create_blob_container(
  Sys.getenv("BLOB_CONTAINER_URL"),
  key = Sys.getenv("STORAGE_ACCOUNT_KEY")
)

multiupload_blob(cont, src = "data/history/*", dest = "data/history")
multiupload_blob(cont, src = "data/futurex/*", dest = "data/futurex")
multiupload_blob(cont, src = "models/*", dest = "models")


# Build worker docker image ----------------------------------------------------

# Review the dockerfile in docker/worker/dockerfile

file.edit(file.path("docker", "worker", "dockerfile"))


# Build and upload the worker docker image to Docker Hub

run(
  "docker build -t %s -f docker/worker/dockerfile .",
  Sys.getenv("WORKER_CONTAINER_IMAGE")
)

run(
  "docker tag %s:latest %s",
  Sys.getenv("WORKER_CONTAINER_IMAGE"),
  Sys.getenv("WORKER_CONTAINER_IMAGE")
)

run("docker push %s", Sys.getenv("WORKER_CONTAINER_IMAGE"))


# Define cluster ---------------------------------------------------------------

# Create json file to store doAzureParallel credentials

create_credentials_json()


# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Create the cluster config file and provision the cluster

create_cluster_json <- function(save_dir = "azure") {
  
  config <- list(
    name = Sys.getenv("CLUSTER_NAME"),
    vmSize = Sys.getenv("VM_SIZE"),
    maxTasksPerNode = 1,
    poolSize = list(
      dedicatedNodes = list(
        min = as.integer(Sys.getenv("NUM_NODES")),
        max = as.integer(Sys.getenv("NUM_NODES"))
      ),
      lowPriorityNodes = list(
        min = 0,
        max = 0
      ),
      autoscaleFormula = "QUEUE_AND_RUNNING"
    ),
    containerImage = Sys.getenv("WORKER_CONTAINER_IMAGE"),
    commandLine = c()
  )
  
  config_json <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(config_json, file = file.path(save_dir, "cluster.json"))
  
}

write_function(create_cluster_json, "R/create_cluster_json.R")

create_cluster_json(save_dir = "azure")
