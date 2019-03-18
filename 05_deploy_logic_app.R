
# 06_deploy_logic_app.R

# This script deploys a Logic App from an Azure Resource Manager (ARM)
# template. The Logic App will create an Azure Container Instance on a schedule
# set to run once a week. The ACI runs the 03_forecast_on_batch.R script to 
# generate forecasts.

# Note: after deploying the ARM template, you must authorize the ACI connector
# in the Azure Portal which gives permission to the Logic App to deploy the ACI.
# See the README.md file for instructions on how to do this.
#
# Run time ~6 minutes on a 5 node cluster


# Deploy Logic App -------------------------------------------------------------

library(dotenv)
library(jsonlite)
library(AzureRMR)
source("R/utilities.R")


# Insert resource names and environment variables into json template

file_name <- file.path("azure", "logic_app_template.json")

logic_app_json <- readChar(file_name, file.info(file_name)$size)

logic_app_json <- replace_template_vars(logic_app_json)

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

# Now see README.md for instructions on how to complete the deployment, including
# authentication of the Logic App ACI connector and enabling the Logic App.
