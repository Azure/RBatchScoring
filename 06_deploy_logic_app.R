
# 05_deploy_logic_app.R

# Enter resource settings ------------------------------------------------------

LOGIC_APP_NAME <- "bfla"
ACI_NAME <- "bfaci"


library(dotenv)
library(jsonlite)
library(AzureRMR)
source("R/utilities.R")

setenv("LOGIC_APP_NAME", LOGIC_APP_NAME)
setenv("ACI_NAME", ACI_NAME)


replace_vars <- function(var_name) {
  pattern <- paste0("\\{", var_name, "\\}")
  gsub(pattern, Sys.getenv(var_name), logic_app_json)
}

file_name <- file.path("azure", "logic_app_template.json")
logic_app_json <- readChar(file_name, file.info(file_name)$size)

vars <- get_env_var_list()

for (var in vars) {
  logic_app_json <- replace_vars(var)
}

write.table(logic_app_json, file.path("azure", "logic_app.json"),
            quote = FALSE, row.names = FALSE, col.names = FALSE)

rg <- az_rm$new(
    tenant = Sys.getenv("TENANT_ID"),
    app = Sys.getenv("SP_NAME"),
    password = Sys.getenv("SP_PASSWORD")
  )$
  get_subscription(Sys.getenv("SUBSCRIPTION_ID"))$
  get_resource_group(Sys.getenv("RESOURCE_GROUP"))


rg$deploy_template(
  name = "bfla",
  template = file.path("azure/logic_app.json")
)

tmp <- rg$get_template("bfla")
tmp$delete(free_resources = TRUE)

run(
  paste("az group deployment create",
    "--name %s",
    "--resource-group %s",
    "--template-file %s"),
    Sys.getenv("LOGIC_APP_NAME"),
    Sys.getenv("RESOURCE_GROUP"),
    "azure/logic_app.json"
)
