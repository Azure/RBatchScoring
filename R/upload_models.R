
library(AzureRMR)
library(AzureStor)

source("R/utilities.R")

key <- ""

ep <- blob_endpoint(
  "https://happypathspublic.blob.core.windows.net",
  key = key)

list_blob_containers(ep)

assets <- blob_container(ep, "assets")

list_blobs(assets)

run(
  "azcopy --source %s --destination %s --dest-key %s --recursive --quiet",
  "models",
  file.path("https://happypathspublic.blob.core.windows.net", "assets", "batch_forecasting"),
  key
)

list_blobs(assets)
