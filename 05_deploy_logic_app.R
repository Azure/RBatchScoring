
# 06_deploy_logic_app.R

# This script deploys a Logic App from an Azure Resource Manager (ARM)
# template. The Logic App will create an Azure Container Instance on a schedule
# set to run once a week. The ACI runs the 04_forecast_on_batch.R script to 
# generate forecasts.

# Note: after deploying the ARM template, you must authorize the ACI connector
# in the Azure Portal which gives permission to the Logic App to deploy the ACI.
# See the README.md file for instructions on how to do this.
#
# The first run of the Logic App will always fail because it is not yet
# authenticated. Once the ACI connector has been authorized, click Run Trigger
# in the Logic App pane to trigger the batch forecasting process.
#
# Run time ~6 minutes on a 5 node cluster


# Deploy Logic App -------------------------------------------------------------

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

library(dotenv)
library(jsonlite)
library(AzureRMR)
source("R/utilities.R")


# Insert resource names and environment variables into json template

file_name <- file.path("azure", "logic_app_template.json")
logic_app_json <- readChar(file_name, file.info(file_name)$size)

replace_vars <- function(var_name) {
  pattern <- paste0("\\{", var_name, "\\}")
  gsub(pattern, get_env(var_name), logic_app_json)
}

vars <- get_dotenv_vars()

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
    get_env("LOGIC_APP_NAME"),
    get_env("RESOURCE_GROUP"),
    "azure/logic_app.json"
)


# Check the provisioning state of the ACI

run(
  "az container show -g %s -n %s -o table",
  get_env("RESOURCE_GROUP"),
  get_env("ACI_NAME")
)


# Check the logs of the ACI. Note that it will take a few minutes for the
# ACI to start up and this command will result in a error if run too soon.

run("az container logs --resource-group %s --name %s",
    get_env("RESOURCE_GROUP"),
    get_env("ACI_NAME")
)

