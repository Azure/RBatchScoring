
# 05_deploy_logic_app.R

# This script will deploy a Logic App from an Azure Resource Manager (ARM)
# template. The Logic App will deploy an Azure Container Instance on a schedule
# to run the 04_forecast_on_batch.R script to generate forecasts.

# Note: after deploying the ARM template, you must authorize the ACI connector
# in the Azure Portal witch gives permission to the Logic App to deploy the ACI.
# The first run of the Logic App will always fail because it is not yet
# authenticated. Once the ACI connector has been authorized, click Run Trigger
# in the Logic App pane to trigger the batch forecasting process.


# Enter resource settings ------------------------------------------------------

LOGIC_APP_NAME <- "bfla"
ACI_NAME <- "bfaci"


# Deploy Logic App -------------------------------------------------------------

library(dotenv)
library(jsonlite)
library(AzureRMR)
source("R/utilities.R")

setenv("LOGIC_APP_NAME", LOGIC_APP_NAME)
setenv("ACI_NAME", ACI_NAME)


# Insert resource names and environment variables into json template

file_name <- file.path("azure", "logic_app_template.json")
logic_app_json <- readChar(file_name, file.info(file_name)$size)

replace_vars <- function(var_name) {
  pattern <- paste0("\\{", var_name, "\\}")
  gsub(pattern, Sys.getenv(var_name), logic_app_json)
}

vars <- get_env_var_list()

for (var in vars) {
  logic_app_json <- replace_vars(var)
}

write.table(logic_app_json, file.path("azure", "logic_app.json"),
            quote = FALSE, row.names = FALSE, col.names = FALSE)


# Deploy the Logic App using the Azure CLI

run(
  paste("az group deployment create",
    "--name %s",
    "--resource-group %s",
    "--template-file %s"),
    Sys.getenv("LOGIC_APP_NAME"),
    Sys.getenv("RESOURCE_GROUP"),
    "azure/logic_app.json"
)

# rg <- az_rm$new(
#     tenant = Sys.getenv("TENANT_ID"),
#     app = Sys.getenv("SP_NAME"),
#     password = Sys.getenv("SP_PASSWORD")
#   )$
#   get_subscription(Sys.getenv("SUBSCRIPTION_ID"))$
#   get_resource_group(Sys.getenv("RESOURCE_GROUP"))
# 
# rg$deploy_template(
#   name = "bfla",
#   template = file.path("azure/logic_app.json"),
#   parameters = list(
#     connections_aci_name = "aci",
#     workflows_bfla_name = "bfla",
#     workflows_bfla_path = "/subscriptions/ff18d7a8-962a-406c-858f-49acd23d6c01/resourceGroups/antabf/providers/Microsoft.ContainerInstance/containerGroups/bfaci"
#   )
# )
# 
# tmp <- rg$get_template("bfla")
# tmp$delete(free_resources = TRUE)