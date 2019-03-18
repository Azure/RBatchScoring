
# 06_delete_resources.R

# This deletes all resources in the deployment resource group, as well as the
# service principal

# Run time ~2 minutes

# Clean up resources -----------------------------------------------------------

library(dotenv)

source("R/utilities.R")

# Delete the resource group

run("az group delete --name %s --yes", get_env("RESOURCE_GROUP"))


# Delete the service principal

run("az ad sp delete --id %s", get_env("SERVICE_PRINCIPAL_APPID"))
