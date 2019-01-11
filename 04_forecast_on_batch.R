
# 04_forecast_at_scale_on_batch.R
# 
# This script generates forecasts for multiple products in parallel on Azure
# Batch.


library(dotenv)
library(jsonlite)
library(doAzureParallel)

source("R/utilities.R")
source("R/options.R")
source("R/create_credentials_json.R")
source("R/create_cluster_json.R")
source("R/create_features.R")
source("R/generate_forecast.R")


# Register batch pool and options for the job ----------------------------------

# If running from script, within docker container, recreate config files from
# environment variables.

if (!interactive()) {
  print("Creating config files")
  create_credentials_json()
  create_cluster_json()
}

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()
azure_options <- list(
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)
file_dir <- "/mnt/batch/tasks/shared/files"
pkgs_to_load <- c("dplyr", "gbm")
vars_to_export <- c("load_model", "load_models", "NLAGS", "FORECAST_HORIZON",
                    "create_features", "QUANTILES", "list_model_names",
                    "list_required_models", "file_dir", "generate_forecast")


# Split product forecasts equally across nodes

chunks <- chunk_by_nodes(floor(TARGET_SKUS / INITIAL_SKUS))


# Generate forecasts

run_batch_jobs <- function(chunks, vars_to_export) {
  
  foreach(
      idx=1:length(chunks),
      .options.azure = azure_options,
      .packages = pkgs_to_load,
      .export = vars_to_export
    ) %dopar% {
    
      
      models <- load_models(file.path(file_dir, "models"))
  
      products <- chunks[[idx]]
      
      for (product in products) {
        
        forecasts <- generate_forecast(
          as.character(product),
          models
        )
        
        write.csv(
          forecasts, 
          file.path(file_dir, "data", "forecasts", paste0(product, ".csv")),
          quote = FALSE, row.names = FALSE
        )
        
      }
      
      # Return arbitrary result                 
      TRUE
                           
    }
}

write_function(run_batch_jobs, "R/run_batch_jobs.R")

system.time({
  run_batch_jobs(chunks, vars_to_export)
})
