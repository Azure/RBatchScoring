######################

# Enter resource names
SUBSCRIPTION_ID <- ""
LOGIC_APP_NAME <- ""
REGION <- ""

######################

library(dotenv)
library(jsonlite)
source("R/utilities.R")

setenv("SUBSCRIPTION_ID", SUBSCRIPTION_ID)
setenv("LOGIC_APP_NAME", LOGIC_APP_NAME)
setenv("REGION", REGION)

replace_vars <- function(var_name) {
  pattern <- paste0("\\{", var_name, "\\}")
  gsub(pattern, Sys.getenv(var_name), logic_app_json)
}

file_name <- file.path("azure", "logic_app_template.json")
logic_app_json <- readChar(file_name, file.info(file_name)$size)

vars <- c("LOGIC_APP_NAME",
          "SUBSCRIPTION_ID",
          "RESOURCE_GROUP",
          "ACI_NAME",
          "REGION",
          "BATCH_ACCOUNT_NAME",
          "BATCH_ACCOUNT_KEY",
          "BATCH_ACCOUNT_URL",
          "STORAGE_ACCOUNT_NAME",
          "STORAGE_ACCOUNT_KEY",
          "STORAGE_ENDPOINT_SUFFIX",
          "FILE_SHARE_NAME",
          "CLUSTER_NAME",
          "VM_SIZE",
          "NUM_NODES",
          "WORKER_CONTAINER_IMAGE",
          "SCHEDULER_CONTAINER_IMAGE")

for (var in vars) {
  logic_app_json <- replace_vars(var)
}

write.table(logic_app_json, file.path("azure", "logic_app.json"),
            quote = FALSE, row.names = FALSE, col.names = FALSE)

run(
  paste("az group deployment create",
    "--name %s",
    "--resource-group %s",
    "--template-file %s"),
    Sys.getenv("LOGIC_APP_NAME"),
    Sys.getenv("RESOURCE_GROUP"),
    "azure/logic_app.json"
)
