
library(dotenv)
library(dplyr)
library(doAzureParallel)
library(gbm)
library(AzureRMR)
library(AzureStor)

source("R/utilities.R")
source("R/options.R")


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

dat <- load_data(file.path("data", "history"))


# Train a single model per time step for steps 1 to 6. Then train one model
# for all subsequent time steps (without lagged features).

# Also train models for quantiles 0.95, 0.75, 0.5, 0.25, 0.05

lagged_feature_steps <- 6

required_models <- list_required_models(lagged_feature_steps, QUANTILES)


# Fix hyperparameters

N.TREES <- 2500
INTERACTION.DEPTH <- 15
SHRINKAGE <- 0.01
N.MINOBSINNODE <- 10


# Train models

result <- foreach(
  
  idx=1:length(required_models),
  .options.azure = azure_options,
  .packages = pkgs_to_load) %dopar% {
                    
    step <- required_models[[idx]]$step
    quantile <- required_models[[idx]]$quantile
                    
    dat <- create_features(dat, step = step, remove_target = FALSE)
    
    if (step <= lagged_feature_steps) {
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
    
    name <- paste0("gbm_t", as.character(step), "_q", as.character(quantile * 100))
    saveRDS(model, file = file.path(file_dir, "models", name))
    
    TRUE
    
  }


# Overwrite model files locally

run(
  "azcopy --source %s --destination %s --source-key %s --quiet --recursive",
  paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
  "models",
  Sys.getenv("STORAGE_ACCOUNT_KEY")
)
