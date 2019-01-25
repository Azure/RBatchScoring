
# 04_forecast_at_scale_on_batch.R
# 
# This script generates forecasts for multiple products in parallel on Azure
# Batch. The doAzureParallel package schedules the jobs to be executed on the
# cluster and manages the job queue. Forecast results are written to the
# File Share.
#
# Run time ~5 minutes on a 5 node cluster


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


# Set the cluster if already exists, otherwise create it

clust <- makeCluster("azure/cluster.json")


# Register the cluster as the doAzureParallel backend
registerDoAzureParallel(clust)

print(paste("Cluster has", getDoParWorkers(), "nodes"))

azure_options <- list(
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)

pkgs_to_load <- c("dplyr", "gbm")
vars_to_export <- c(
    "NLAGS",
    "FORECAST_HORIZON",
    "QUANTILES",
    "load_model",
    "load_models",
    "create_features",
    "list_model_names",
    "list_required_models",
    "generate_forecast"
  )


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
    
      file_dir <- "/mnt/batch/tasks/shared/files"
      
      models <- load_models(file.path(file_dir, "models"))
      
  
      products <- chunks[[idx]]
      
      for (product in products) {
        
        history <- read.csv(
          file.path(file_dir,
                    "data", "history",
                    paste0("product", product, ".csv"))
        ) %>%
          select(sku, store, week, sales)
        
        futurex <- read.csv(
          file.path(file_dir,
                    "data", "futurex",
                    paste0("product", product, ".csv"))
        )
        
        forecasts <- generate_forecast(
          futurex,
          history,
          models
        )
        
        write.csv(
          forecasts, 
          file.path(
            file_dir, "data", "forecasts",
            paste0("product", product, ".csv")),
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


# Delete the cluster

stopCluster(clust)


# Plot results to validate

if (interactive()) {
  library(ggplot2)
  library(dplyr)
  library(AzureStor)

  local_file <- file.path("data", "forecasts", "product1.csv")
  download_from_url(
    src = paste0(Sys.getenv("FILE_SHARE_URL"), "data/forecasts/product1.csv"),
    dest = local_file,
    key = Sys.getenv("STORAGE_ACCOUNT_KEY"),
    overwrite = TRUE
  )

  read.csv(local_file) %>%
    filter(store == 2, sku %in% 1:4) %>%
    select(week, sku, q5:q95) %>%
    ggplot(aes(x = week)) +
    facet_grid(rows = vars(sku), scales = "free_y") +
    geom_ribbon(aes(ymin = q5, ymax = q95, fill = "q5-q95"), alpha = .25) + 
    geom_ribbon(aes(ymin = q25, ymax = q75, fill = "q25-q75"), alpha = .25) +
    geom_line(aes(y = q50, colour = "q50"), linetype="dashed") +
    scale_y_log10() +
    scale_fill_manual(name = "", values = c("q25-q75" = "red", "q5-q95" = "blue")) +
    scale_colour_manual(name = "", values = c("q50" = "black")) +
    theme(
      axis.text.y=element_blank(),
      axis.ticks.y=element_blank(),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    ) +
    labs(y = "forecast sales") +
    ggtitle(paste("Forecasts for SKUs 1 to 4 in store 2"))
}
