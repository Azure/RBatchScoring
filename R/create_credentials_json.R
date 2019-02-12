create_credentials_json <- function(save_dir = "azure",
                                    print_json = TRUE) {
  
  resource_id_prefix <- paste(
    "/subscriptions", Sys.getenv("SUBSCRIPTION_ID"), "resourceGroups",
    Sys.getenv("RESOURCE_GROUP"), "providers", sep = "/")
  
  batch_account_resource_id <- paste(
    resource_id_prefix, "Microsoft.Batch", "batchAccounts",
    Sys.getenv("BATCH_ACCOUNT_NAME"), sep = "/")
  
  storage_account_resource_id <- paste(
    resource_id_prefix, "Microsoft.Storage", "storageAccounts",
    Sys.getenv("STORAGE_ACCOUNT_NAME"), sep = "/")
  
  credentials <- list(
    servicePrincipal = list(
      tenantId = Sys.getenv("TENANT_ID"),
      storageEndpointSuffix = "core.windows.net",
      batchAccountResourceId = batch_account_resource_id,
      storageAccountResourceId = storage_account_resource_id,
      credential = Sys.getenv("SERVICE_PRINCIPAL_CRED"),
      clientId = Sys.getenv("SERVICE_PRINCIPAL_APPID")
    )
  )
  
  credentials_json <- toJSON(credentials, auto_unbox = TRUE, pretty = TRUE)
  
  write(credentials_json, file = file.path(save_dir, "credentials.json"))
  
  if (print_json) print(credentials_json)
  
}