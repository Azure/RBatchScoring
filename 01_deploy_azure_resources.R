
# 01_deploy_azure_resources.R
# 
# This script sets up Azure resources including the Batch cluster and the file
# share where the data will be stored. The docker image to be deployed on each
# cluster node is defined and pushed to Docker Hub.
#
# Note: you must have run the setup script for doAzureParallel using
# service principal deployment and copied the output to azure/credentials.json


# Enter resource settings ------------------------------------------------------

FILE_SHARE_NAME <- "bffs"
CLUSTER_NAME <- "bfclust"
WORKER_CONTAINER_IMAGE <- "angusrtaylor/bfworker"
VM_SIZE <- "Standard_DS2_v2"
NUM_NODES <- "10"


# Set environment variables -----------------------------------------------


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
  tenant=Sys.getenv("TENANT_ID"),
  app=Sys.getenv("SP_NAME"),
  password=Sys.getenv("SP_PASSWORD")
)

az_sub <- az$get_subscription(Sys.getenv("SUBSCRIPTION_ID"))

rg <- az_sub$get_resource_group(Sys.getenv("RESOURCE_GROUP"))

setenv("REGION", rg$location)
setenv(
  "STORAGE_ACCOUNT_KEY",
  rg$get_storage_account(Sys.getenv("STORAGE_ACCOUNT_NAME"))$list_keys()[[1]]
)


# Create file share and directory structure -------------------------------

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


# Retrieve pre-trained forecasting models --------------------------------------

# Download from blob storage

create_dir("models")

run(
  "azcopy --source %s --destination %s --quiet --recursive",
  file.path(
    "https://happypathspublic.blob.core.windows.net",
    "assets",
    "batch_forecasting"
  ),
  "models"
)

run("ls models")

# Transfer models to file share

run(
  "azcopy --source %s --destination %s --dest-key %s --quiet --recursive",
  "models",
  paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
  Sys.getenv("STORAGE_ACCOUNT_KEY")
)


# Build worker docker image -----------------------------------------------

# Build and upload the worker docker image to docker hub. Review the dockerfile
# in docker/worker/dockerfile

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


# Provision cluster -------------------------------------------------------

# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Create the cluster config file and provision the cluster

create_cluster_json(save_dir = "azure")
cluster <- makeCluster("azure/cluster.json")
