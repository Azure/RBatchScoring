# create_credentials_json <- function() {
#   
#   credentials <- list(
#     batchAccount = list(
#       url = Sys.getenv("BATCH_ACCOUNT_URL"),
#       name = Sys.getenv("BATCH_ACCOUNT_NAME"),
#       key = Sys.getenv("BATCH_ACCOUNT_KEY")
#     ),
#     storageAccount = list(
#       endpointSuffix = Sys.getenv("STORAGE_ENDPOINT_SUFFIX"),
#       name = Sys.getenv("STORAGE_ACCOUNT_NAME"),
#       key = Sys.getenv("STORAGE_ACCOUNT_KEY")
#     )
#   )
#   
#   credentials_json <- toJSON(credentials, auto_unbox = TRUE, pretty = TRUE)
#   
#   write(credentials_json, file = file.path("credentials.json"))
#   
# }

create_credentials_json <- function() {
  
  credentials <- list(
    servicePrincipal = list(
      tenantId = Sys.getenv("TENANT_ID"),
      storageEndpointSuffix = Sys.getenv("STORAGE_ENDPOINT_SUFFIX"),
      batchAccountResourceId = Sys.getenv("BATCH_ACCOUNT_RESOURCE_ID"),
      storageAccountResourceId = Sys.getenv("STORAGE_ACCOUNT_RESOURCE_ID"),
      credential = Sys.getenv("SP_PASSWORD"),
      clientId = Sys.getenv("SP_APP")
      
    )
  )
  
  credentials_json <- toJSON(credentials, auto_unbox = TRUE, pretty = TRUE)
  
  write(credentials_json, file = file.path("credentials.json"))
  
}