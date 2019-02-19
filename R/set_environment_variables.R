
set_environment_variables <- function() {
  
  # Create or replace a .env file to hold secrets
  invisible({
    if (file.exists(".env")) file.remove(".env")
    file.create(".env")
  })
  
  source("resource_specs.R")
  
  envs <- c(
    "SUBSCRIPTION_ID",
    "TENANT_ID",
    "SERVICE_PRINCIPAL_NAME",
    "REGION",
    "RESOURCE_GROUP",
    "BATCH_ACCOUNT_NAME",
    "STORAGE_ACCOUNT_NAME",
    "BLOB_CONTAINER_NAME",
    "LOGIC_APP_NAME",
    "ACI_NAME",
    "CLUSTER_NAME",
    "VM_SIZE",
    "NUM_NODES",
    "WORKER_CONTAINER_IMAGE",
    "SCHEDULER_CONTAINER_IMAGE"
  )
  
  invisible(lapply(envs, function(e) setenv(e, eval(parse(text=e)))))
  
}

