
# 02_deploy_azure_resources.R
# 
# This script sets up Azure resources including the Batch cluster and the file
# share where the data will be stored. The original dataset replicated from 11
# SKUs of one product to 1000 SKUs of 90 products. The docker image to be 
# deployed on each cluster node is defined and pushed to your Docker Hub account.
#
# Note: you must have run the setup script for doAzureParallel using
# service principal deployment and copied the output to azure/credentials.json.
# Additionally, you must have logged in to your Docker Hub account.
#
# Run time ~4 minutes


# Enter resource settings ------------------------------------------------------

FILE_SHARE_NAME <- ""         # e.g. bffs
CLUSTER_NAME <- ""            # e.g. bfcl
WORKER_CONTAINER_IMAGE <- ""  # e.g. <your-docker-id>/bfworker
VM_SIZE <- ""                 # e.g. Standard_DS2_v2
NUM_NODES <- ""               # e.g. 5


# Set environment variables ----------------------------------------------------

library(jsonlite)
library(doAzureParallel)
library(AzureRMR)
library(AzureStor)

source("R/options.R")
source("R/utilities.R")
source("R/create_cluster_json.R")


# Create a .env file to hold secrets

run("touch .env")


# Set R environment variables and add to .env file

setenv("FILE_SHARE_NAME", FILE_SHARE_NAME)
setenv("CLUSTER_NAME", CLUSTER_NAME)
setenv("WORKER_CONTAINER_IMAGE", WORKER_CONTAINER_IMAGE)
setenv("VM_SIZE", VM_SIZE)
setenv("NUM_NODES", NUM_NODES)


# Get env variables from doAzureParallel credentials file

credentials <- fromJSON(file.path("azure", "credentials.json"))$servicePrincipal

setenv(
  "RESOURCE_GROUP",
  unlist(strsplit(credentials$batchAccountResourceId, "/"))[[5]]
)
setenv("TENANT_ID", credentials$tenantId)
setenv("SP_NAME", credentials$clientId)
setenv("SP_PASSWORD", credentials$credential)
setenv(
  "SUBSCRIPTION_ID",
  unlist(strsplit(credentials$batchAccountResourceId, "/"))[[3]]
)
setenv(
  "STORAGE_ACCOUNT_NAME",
  unlist(strsplit(credentials$storageAccountResourceId, "/"))[[9]]
)
setenv("STORAGE_ENDPOINT_SUFFIX", credentials$storageEndpointSuffix)
setenv("BATCH_ACCOUNT_RESOURCE_ID", credentials$batchAccountResourceId)
setenv("STORAGE_ACCOUNT_RESOURCE_ID", credentials$storageAccountResourceId)
setenv("FILE_SHARE_URL",
       paste0(
         "https://", Sys.getenv("STORAGE_ACCOUNT_NAME"),
         ".file.core.windows.net/", Sys.getenv("FILE_SHARE_NAME"), "/"
       )
)


# Get env variables from resource group / storage account

az <- az_rm$new(
  tenant = Sys.getenv("TENANT_ID"),
  app = Sys.getenv("SP_NAME"),
  password = Sys.getenv("SP_PASSWORD")
)

az_sub <- az$get_subscription(Sys.getenv("SUBSCRIPTION_ID"))
rg <- az_sub$get_resource_group(Sys.getenv("RESOURCE_GROUP"))

setenv("REGION", rg$location)
setenv(
  "STORAGE_ACCOUNT_KEY",
  rg$get_storage_account(Sys.getenv("STORAGE_ACCOUNT_NAME"))$list_keys()[[1]]
)


# Create file share and directory structure ------------------------------------

create_file_share(
  Sys.getenv("FILE_SHARE_URL"),
  key = Sys.getenv("STORAGE_ACCOUNT_KEY")
)

fs <- file_share(
  Sys.getenv("FILE_SHARE_URL"),
  key = Sys.getenv("STORAGE_ACCOUNT_KEY")
)

create_azure_dir(fs, "models")
create_azure_dir(fs, "data")
create_azure_dir(fs, file.path("data", "futurex"))
create_azure_dir(fs, file.path("data", "history"))
create_azure_dir(fs, file.path("data", "forecasts"))


# Replicate data ---------------------------------------------------------------

# Factor by which to replicate products. Expand to 1000 SKUs from 90 products

multiplier <- floor(TARGET_SKUS / 11)

for (m in 2:multiplier) {
  run("cp data/history/product1.csv data/history/product%s.csv", m)
  run("cp data/futurex/product1.csv data/futurex/product%s.csv", m)
}


# Upload to File Share using Az Copy

run(
  "azcopy --source %s --destination %s --dest-key %s --quiet --recursive",
  file.path("data", "history"),
  paste0(Sys.getenv("FILE_SHARE_URL"), "data/history"),
  Sys.getenv("STORAGE_ACCOUNT_KEY")
)

run(
  "azcopy --source %s --destination %s --dest-key %s --quiet --recursive",
  file.path("data", "futurex"),
  paste0(Sys.getenv("FILE_SHARE_URL"), "data/futurex"),
  Sys.getenv("STORAGE_ACCOUNT_KEY")
)


# Transfer pre-trained forecasting models to File Share ------------------------

run(
  "azcopy --source %s --destination %s --dest-key %s --quiet --recursive",
  "models",
  paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
  Sys.getenv("STORAGE_ACCOUNT_KEY")
)


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


# Provision cluster ------------------------------------------------------------

# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Create the cluster config file and provision the cluster

create_cluster_json <- function(save_dir) {
  
  mount_str <- paste(
    "mount -t cifs //%s.file.core.windows.net/%s /mnt/batch/tasks/shared/files",
    "-o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,sec=ntlmssp"
  )
  mount_cmd <- sprintf(
    mount_str,
    Sys.getenv("STORAGE_ACCOUNT_NAME"),
    Sys.getenv("FILE_SHARE_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_KEY")
  )
  cmd_line <- c("mkdir /mnt/batch/tasks/shared/files", mount_cmd)
  
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
    commandLine = cmd_line
  )
  
  config_json <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(config_json, file = file.path(save_dir, "cluster.json"))
  
}

write_function(create_cluster_json, "R/create_cluster_json.R")

create_cluster_json(save_dir = "azure")
cluster <- makeCluster("azure/cluster.json")
