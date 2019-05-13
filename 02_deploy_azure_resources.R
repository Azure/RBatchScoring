
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
library(AzureContainers)

source("R/options.R")
source("R/utilities.R")
source("R/create_cluster_json.R")
source("R/create_credentials_json.R")

set_resource_specs()

# Create resource group

az <- AzureRMR::get_azure_login()
sub <- az$get_subscription(get_env("SUBSCRIPTION_ID"))
rg <- sub$create_resource_group(get_env("RESOURCE_GROUP"), location=get_env("REGION"))


# Create service principal

gr <- AzureGraph::get_graph_login()
app <- gr$create_app(get_env("SERVICE_PRINCIPAL_NAME"))

rg$add_role_assignment(app, "Contributor")

set_env("SERVICE_PRINCIPAL_APPID", app$properties$appId)
set_env("SERVICE_PRINCIPAL_CRED", app$password)


# Create storage account and container

stor <- rg$create_storage_account(get_env("STORAGE_ACCOUNT_NAME"), kind="BlobStorage")

set_env("STORAGE_ACCOUNT_KEY", stor$list_keys()[1])

endp <- stor$get_blob_endpoint()
cont <- create_blob_container(endp, get_env("BLOB_CONTAINER_NAME"))

set_env("BLOB_CONTAINER_URL", file.path(cont$endpoint$url, cont$name, "/"))


# Create batch account

rg$create_resource(type="Microsoft.Batch/batchAccounts", name=get_env("BATCH_ACCOUNT_NAME"),
  properties=list(AutoStorage=stor$id))

# run(
#   paste("az batch account create",
#         "--name %s --resource-group %s --location %s --storage-account %s",
#         "--query provisioningState"),
#   get_env("BATCH_ACCOUNT_NAME"), get_env("RESOURCE_GROUP"),
#   get_env("REGION"), get_env("STORAGE_ACCOUNT_NAME")
# )


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


# upload resources -------------------------------------------------------------

multiupload_blob(cont, src = "data/history/*", dest = "data/history")
multiupload_blob(cont, src = "data/futurex/*", dest = "data/futurex")
multiupload_blob(cont, src = "models/*", dest = "models")


# Build worker docker image ----------------------------------------------------

# The worker docker container will be deployed on each node of the Batch cluster.
# The dockerfile used to build to the worker docker image can be reviewed in
# docker/worker/dockerfile


# Build and upload the worker docker image to Docker Hub

call_docker(sprintf("build -t %s -f docker/worker/dockerfile .",
            paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE"))
))

call_docker(sprintf("tag %s:latest %s",
            paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE")),
            paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE"))
))

call_docker(sprintf("sudo docker push %s",
            paste0(get_env("DOCKER_ID"), "/", get_env("WORKER_CONTAINER_IMAGE"))))


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
        min = as.integer(get_env("NUM_NODES")),
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
