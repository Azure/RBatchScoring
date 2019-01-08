######################

# Enter resource names
#RESOURCE_GROUP <- "antabf"
FILE_SHARE_NAME <- "bffs"
CLUSTER_NAME <- "bfclust"
WORKER_CONTAINER_IMAGE <- "angusrtaylor/bfworker"
VM_SIZE <- "Standard_DS2_v2"
NUM_NODES <- "10"
  
######################

library(jsonlite)
library(doAzureParallel)
library(AzureRMR)
library(AzureStor)

source("R/utilities.R")
source("R/create_cluster_json.R")


# Create a .env file

run("touch .env")


# Set R environment variables and add to .env file

setenv("FILE_SHARE_NAME", FILE_SHARE_NAME)
setenv("CLUSTER_NAME", CLUSTER_NAME)
setenv("WORKER_CONTAINER_IMAGE", WORKER_CONTAINER_IMAGE)
setenv("VM_SIZE", VM_SIZE)
setenv("NUM_NODES", NUM_NODES)


# Get env variables from doAzureParallel credentials file

credentials <- fromJSON(file.path("azure", "credentials.json"))$servicePrincipal

setenv("RESOURCE_GROUP", unlist(strsplit(credentials$batchAccountResourceId, "/"))[[5]])
setenv("TENANT_ID", credentials$tenantId)
setenv("SP_NAME", credentials$clientId)
setenv("SP_PASSWORD", credentials$credential)
setenv("SUBSCRIPTION_ID", unlist(strsplit(credentials$batchAccountResourceId, "/"))[[3]])
setenv("STORAGE_ACCOUNT_NAME", unlist(strsplit(credentials$storageAccountResourceId, "/"))[[9]])
setenv("STORAGE_ENDPOINT_SUFFIX", credentials$storageEndpointSuffix)
setenv("BATCH_ACCOUNT_RESOURCE_ID", credentials$batchAccountResourceId)
setenv("STORAGE_ACCOUNT_RESOURCE_ID", credentials$storageAccountResourceId)
setenv("FILE_SHARE_URL",
       paste0("https://", Sys.getenv("STORAGE_ACCOUNT_NAME"),
              ".file.core.windows.net/", Sys.getenv("FILE_SHARE_NAME"), "/")
)


# Get env variables from resource group / storage account

az <- az_rm$new(tenant=Sys.getenv("TENANT_ID"),
                app=Sys.getenv("SP_NAME"),
                password=Sys.getenv("SP_PASSWORD"))

az_sub <- az$get_subscription(Sys.getenv("SUBSCRIPTION_ID"))

rg <- az_sub$get_resource_group(Sys.getenv("RESOURCE_GROUP"))

setenv("REGION", rg$location)
setenv("STORAGE_ACCOUNT_KEY",
       rg$get_storage_account(
         Sys.getenv("STORAGE_ACCOUNT_NAME")
         )$list_keys()[[1]]
       )


# Create file share and directory structure

create_file_share(Sys.getenv("FILE_SHARE_URL"),
                  key = Sys.getenv("STORAGE_ACCOUNT_KEY"))

fs <- file_share(Sys.getenv("FILE_SHARE_URL"),
                         key = Sys.getenv("STORAGE_ACCOUNT_KEY"))
create_azure_dir(fs, "models")
create_azure_dir(fs, "data")
create_azure_dir(fs, file.path("data", "small"))
create_azure_dir(fs, file.path("data", "large"))
create_azure_dir(fs, file.path("data", "large", "futurex"))
create_azure_dir(fs, file.path("data", "large", "history"))
create_azure_dir(fs, file.path("data", "large", "forecasts"))


# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Build and upload the worker docker image to docker hub

run("docker build -t %s -f docker/worker/dockerfile .", Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker tag %s:latest %s", Sys.getenv("WORKER_CONTAINER_IMAGE"), Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker push %s", Sys.getenv("WORKER_CONTAINER_IMAGE"))


# Create the cluster config file and provision the cluster

create_cluster_json(save_dir = "azure")
cluster <- makeCluster("azure/cluster.json")
