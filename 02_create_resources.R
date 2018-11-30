######################

# Enter resource names
RESOURCE_GROUP <- "bfrg"
FILE_SHARE_NAME <- "bffs"
CLUSTER_NAME <- "bfclust"
WORKER_CONTAINER_IMAGE <- ""
VM_SIZE <- "Standard_DS3_v2"
NUM_NODES <- "5"
  
######################

library(jsonlite)
library(doAzureParallel)

source("R/utilities.R")
source("R/create_cluster_config.R")


# Create a .env file

run("touch .env")


# Create azure credentials file. Paste doAzureParallel setup output in this file.

run("touch azure/credentials.json")


# Get environment variables from credentials.json

credentials <- fromJSON(file.path("azure", "credentials.json"))


# Set R environment variables and add to .env file

setenv("RESOURCE_GROUP", RESOURCE_GROUP)
setenv("FILE_SHARE_NAME", FILE_SHARE_NAME)
setenv("STORAGE_ACCOUNT_NAME", credentials$storageAccount$name)
setenv("STORAGE_ACCOUNT_KEY", credentials$storageAccount$key)
setenv("STORAGE_ENDPOINT_SUFFIX", credentials$storageAccount$endpointSuffix)
setenv("BATCH_ACCOUNT_URL", credentials$batchAccount$url)
setenv("BATCH_ACCOUNT_NAME", credentials$batchAccount$name)
setenv("BATCH_ACCOUNT_KEY", credentials$batchAccount$key)
setenv("FILE_SHARE_URL",
       paste0("https://", Sys.getenv("STORAGE_ACCOUNT_NAME"),
              ".file.core.windows.net/", Sys.getenv("FILE_SHARE_NAME"), "/")
)
setenv("CLUSTER_NAME", CLUSTER_NAME)
setenv("WORKER_CONTAINER_IMAGE", WORKER_CONTAINER_IMAGE)
setenv("VM_SIZE", VM_SIZE)
setenv("NUM_NODES", NUM_NODES)


# Create file share

run("az storage share create -n %s --account-name %s",
    Sys.getenv("FILE_SHARE_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_NAME")
)


# Upload data files to file share using azcopy

run("azcopy --source %s --destination %s --dest-key %s --recursive",
    "data/",
    paste0(Sys.getenv("FILE_SHARE_URL"), "data/"),
    Sys.getenv("STORAGE_ACCOUNT_KEY")
)


# Create a directory to store forecasts

run("az storage directory create --account-name %s --account-key %s --share-name %s --name forecasts",
    Sys.getenv("STORAGE_ACCOUNT_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_KEY"),
    Sys.getenv("FILE_SHARE_NAME")
)


# Set doAzureParallel credentials

doAzureParallel::setCredentials("azure/credentials.json")


# Create the cluster config file and provision the cluster

create_cluster_config(save_dir = "azure")
cluster <- makeCluster("azure/cluster.json")
