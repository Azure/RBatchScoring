
# 03_(optional)_train_forecasting_models.R
# 
# This script trains GBM forecasting models for the 13 time steps in the
# forecast horizon and 5 quantiles. Trained models will be saved directly
# to the File Share, overwriting any models that already exist there.


library(dotenv)
library(jsonlite)
library(doAzureParallel)

source("R/utilities.R")
source("R/options.R")
source("R/create_credentials_json.R")
source("R/create_cluster_json.R")
source("R/create_features.R")


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


# Define which local objects should be exported to the job environment.

vars_to_export <- c(
  "dat",
  "file_dir",
  "required_models",
  "QUANTILES",
  "INTERACTION.DEPTH",
  "N.MINOBSINNODE",
  "N.TREES",
  "SHRINKAGE"
)

dat <- read.csv(file.path("data", "history", "product1.csv"))


# Train a single model per time step and quantile for steps 1 to 6. Then train
# one model per quantile for all subsequent time steps (without lagged features).

required_models <- list_required_models(
    lagged_feature_steps = 6, 
    quantiles = QUANTILES
  )


# Train models

result <- foreach(
  
  idx=1:length(required_models),
  .options.azure = azure_options,
  .packages = pkgs_to_load,
  .export = vars_to_export) %dopar% {
                    
    step <- required_models[[idx]]$step
    quantile <- required_models[[idx]]$quantile
                    
    dat <- create_features(dat, step = step, remove_target = FALSE)
    
    if (step <= 6) {
      form <- as.formula(
        paste("sales ~ sku + deal + feat + level +",
              "month_mean + month_max + month_min + lag1 +",
              paste(paste0("price", 1:11), collapse = " + ")
        )
      )
    } else {
      form <- as.formula(
        paste("sales ~ sku + deal + feat + level +",
              paste(paste0("price", 1:11), collapse = " + ")
              )
      )
    }
    
    model <- gbm(
      form,
      distribution = list(name = "quantile", alpha = quantile),
      data = dat,
      n.trees = N.TREES,
      interaction.depth = INTERACTION.DEPTH,
      n.minobsinnode = N.MINOBSINNODE,
      shrinkage = SHRINKAGE,
      keep.data = FALSE
    )
    
    model$data <- NULL
    
    name <- paste0("gbm_t", as.character(step), "_q",
                   as.character(quantile * 100))
    saveRDS(model, file = file.path(file_dir, "models", name))
    
    
    # Return arbitrary result
    
    TRUE
    
  }


# Overwrite model files locally

if (interactive()) {
  run(
    "azcopy --source %s --destination %s --source-key %s --quiet --recursive",
    paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
    "models",
    Sys.getenv("STORAGE_ACCOUNT_KEY")
  )
}
