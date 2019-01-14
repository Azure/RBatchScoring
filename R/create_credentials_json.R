create_credentials_json <- function(save_dir = "azure",
                                    print_json = TRUE) {
  
  credentials <- list(
    servicePrincipal = list(
      tenantId = Sys.getenv("TENANT_ID"),
      storageEndpointSuffix = Sys.getenv("STORAGE_ENDPOINT_SUFFIX"),
      batchAccountResourceId = Sys.getenv("BATCH_ACCOUNT_RESOURCE_ID"),
      storageAccountResourceId = Sys.getenv("STORAGE_ACCOUNT_RESOURCE_ID"),
      credential = Sys.getenv("SP_PASSWORD"),
      clientId = Sys.getenv("SP_NAME")
    )
  )
  
  credentials_json <- toJSON(credentials, auto_unbox = TRUE, pretty = TRUE)
  
  write(credentials_json, file = file.path(save_dir, "credentials.json"))
  
  if (print_json) print(credentials_json)
  
}