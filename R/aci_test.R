
# 05_run_job_from_docker.R
# 
# This script defines a docker image for the job scheduler. The forecast
# generation process is then triggered from a docker container running locally.


# Enter resource settings ------------------------------------------------------

SCHEDULER_CONTAINER_IMAGE <- "angusrtaylor/bfscheduler"


# Define docker image -----------------------------------------------------

library(dotenv)
source("R/utilities.R")
# source("R/options.R")
# source("R/create_features.R")
# source("R/generate_forecast.R")
# source("R/run_batch_jobs.R")

setenv("SCHEDULER_CONTAINER_IMAGE", SCHEDULER_CONTAINER_IMAGE)


# Build scheduler docker image

run("docker build -t %s -f docker/scheduler/dockerfile .", Sys.getenv("SCHEDULER_CONTAINER_IMAGE"))
run("docker tag %s:latest %s", Sys.getenv("SCHEDULER_CONTAINER_IMAGE"), Sys.getenv("SCHEDULER_CONTAINER_IMAGE"))
run("docker push %s", Sys.getenv("SCHEDULER_CONTAINER_IMAGE"))


# Run in the docker container

get_env_var_list <- function() {
  unique(
    unlist(
      lapply(readLines(".env"), function(x) strsplit(x, "=")[[1]][1]
      )
    )
  )
}

env_vars <- get_env_var_list

run(
  paste("docker run", 
        paste0("-e ", env_vars, "=", Sys.getenv(env_vars), collapse = " "),
        Sys.getenv("SCHEDULER_CONTAINER_IMAGE")
  )
)


run("docker run -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s -e %s=%s %s",
    "BATCH_ACCOUNT_NAME", Sys.getenv("BATCH_ACCOUNT_NAME"),
    "BATCH_ACCOUNT_KEY", Sys.getenv("BATCH_ACCOUNT_KEY"),
    "BATCH_ACCOUNT_URL", Sys.getenv("BATCH_ACCOUNT_URL"),
    "STORAGE_ENDPOINT_SUFFIX", Sys.getenv("STORAGE_ENDPOINT_SUFFIX"),
    "STORAGE_ACCOUNT_NAME", Sys.getenv("STORAGE_ACCOUNT_NAME"),
    "STORAGE_ACCOUNT_KEY", Sys.getenv("STORAGE_ACCOUNT_KEY"),
    "FILE_SHARE_NAME", Sys.getenv("FILE_SHARE_NAME"),
    "CLUSTER_NAME", Sys.getenv("CLUSTER_NAME"),
    "VM_SIZE", Sys.getenv("VM_SIZE"),
    "NUM_NODES", Sys.getenv("NUM_NODES"),
    "WORKER_CONTAINER_IMAGE", Sys.getenv("WORKER_CONTAINER_IMAGE"),
    Sys.getenv("SCHEDULER_CONTAINER_IMAGE")
)


# Test in Azure Container Instance

run(
  paste("az container create --resource-group %s",
        "--azure-file-volume-account-key %s",
        "--azure-file-volume-account-name %s",
        "--azure-file-volume-mount-path %s",
        "--azure-file-volume-share-name %s",
        "--cpu %s",
        "--environment-variables %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s",
        "--image %s",
        "--memory %s",
        "--name %s",
        "--os-type %s",
        "--restart-policy %s"),
  Sys.getenv("RESOURCE_GROUP"),
  Sys.getenv("STORAGE_ACCOUNT_KEY"),
  Sys.getenv("STORAGE_ACCOUNT_NAME"),
  "/mnt/batch/tasks/shared/files",
  Sys.getenv("FILE_SHARE_NAME"),
  "4",
  "BATCH_ACCOUNT_NAME", Sys.getenv("BATCH_ACCOUNT_NAME"),
  "BATCH_ACCOUNT_KEY", Sys.getenv("BATCH_ACCOUNT_KEY"),
  "BATCH_ACCOUNT_URL", Sys.getenv("BATCH_ACCOUNT_URL"),
  "STORAGE_ENDPOINT_SUFFIX", Sys.getenv("STORAGE_ENDPOINT_SUFFIX"),
  "STORAGE_ACCOUNT_NAME", Sys.getenv("STORAGE_ACCOUNT_NAME"),
  "STORAGE_ACCOUNT_KEY", Sys.getenv("STORAGE_ACCOUNT_KEY"),
  "FILE_SHARE_NAME", Sys.getenv("FILE_SHARE_NAME"),
  "CLUSTER_NAME", Sys.getenv("CLUSTER_NAME"),
  "VM_SIZE", Sys.getenv("VM_SIZE"),
  "NUM_NODES", Sys.getenv("NUM_NODES"),
  "WORKER_CONTAINER_IMAGE", Sys.getenv("WORKER_CONTAINER_IMAGE"),
  Sys.getenv("SCHEDULER_CONTAINER_IMAGE"),
  "14",
  Sys.getenv("ACI_NAME"),
  "Linux",
  "OnFailure"
)

run("az container logs --name %s --resource-group %s", Sys.getenv("ACI_NAME"), Sys.getenv("RESOURCE_GROUP"))

run("az container delete --name %s --resource-group %s --yes",
    Sys.getenv("ACI_NAME"), Sys.getenv("RESOURCE_GROUP"))
