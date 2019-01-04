#NEW PROCESS:
#01_deploy_azure_resoures (with create file share and directories)
#02_extract_explore_expand_data (with doAzureParallel)



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

#setenv("REGION", unlist(strsplit(credentials$batchAccount$url, "\\."))[2])
#setenv("STORAGE_ACCOUNT_NAME", credentials$storageAccount$name)
#setenv("STORAGE_ACCOUNT_KEY", credentials$storageAccount$key)
#setenv("STORAGE_ENDPOINT_SUFFIX", credentials$storageAccount$endpointSuffix)
#setenv("BATCH_ACCOUNT_URL", credentials$batchAccount$url)
#setenv("BATCH_ACCOUNT_NAME", credentials$batchAccount$name)
#setenv("BATCH_ACCOUNT_KEY", credentials$batchAccount$key)


# Create file share and directory structure

create_file_share(Sys.getenv("FILE_SHARE_URL"),
                  key = Sys.getenv("STORAGE_ACCOUNT_KEY"))

#run("az storage share create -n %s --account-name %s",
#    Sys.getenv("FILE_SHARE_NAME"),
#    Sys.getenv("STORAGE_ACCOUNT_NAME")
#)

fs <- file_share(Sys.getenv("FILE_SHARE_URL"),
                         key = Sys.getenv("STORAGE_ACCOUNT_KEY"))
create_azure_dir(fs, "data")
create_azure_dir(fs, file.path("data", "small"))
create_azure_dir(fs, file.path("data", "large"))
create_azure_dir(fs, file.path("data", "large", "futurex"))
create_azure_dir(fs, file.path("data", "large", "history"))
create_azure_dir(fs, file.path("data", "large", "forecasts"))

# files <- c(
#   list.files(file.path("data", "scoring", "futurex"), full.names = TRUE),
#   list.files(file.path("data", "scoring", "history"), full.names = TRUE)
# )
# system.time({
#   lapply(files, function(f)
#          upload_to_url(
#            f,
#            file.path(Sys.getenv("FILE_SHARE_URL"), f),
#            key = Sys.getenv("STORAGE_ACCOUNT_KEY")
#          ))
# })

# Upload data files to file share

# run("azcopy --source %s --destination %s --dest-key %s --recursive",
#     "data/history",
#     paste0(Sys.getenv("FILE_SHARE_URL"), "data/history"),
#     Sys.getenv("STORAGE_ACCOUNT_KEY")
# )
# 
# run("azcopy --source %s --destination %s --dest-key %s --recursive",
#     "data/futurex",
#     paste0(Sys.getenv("FILE_SHARE_URL"), "data/futurex"),
#     Sys.getenv("STORAGE_ACCOUNT_KEY")
# )


# Create a directory to store forecasts

# run("az storage directory create --account-name %s --account-key %s --share-name %s --name forecasts",
#     Sys.getenv("STORAGE_ACCOUNT_NAME"),
#     Sys.getenv("STORAGE_ACCOUNT_KEY"),
#     Sys.getenv("FILE_SHARE_NAME")
# )


# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Build and upload the worker docker image to docker hub

run("docker build -t %s -f docker/worker/dockerfile .", Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker tag %s:latest %s", Sys.getenv("WORKER_CONTAINER_IMAGE"), Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker push %s", Sys.getenv("WORKER_CONTAINER_IMAGE"))


# Create the cluster config file and provision the cluster

create_cluster_json(save_dir = "azure")
cluster <- makeCluster("azure/cluster.json")
