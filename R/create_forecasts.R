
library(forecastHybrid)
library(dplyr)
library(lubridate)
library(tidyr)
library(jsonlite)
library(doAzureParallel)
source("R/settings.R")
source("R/utilities.R")
source("R/get_data.R")

NUM_TIME_SERIES <- 100

series_list <- load_data("data")[1:NUM_TIME_SERIES]

generate_forecast <- function(ts_idx) {
  series <- df2ts(series_list[[ts_idx]])$train
  series <- window(series, 1990)
  hybrid <- hybridModel(y = series,
                        weights = "equal",
                        errorMethod = "MAE",
                        models = MODELS,
                        lambda = "auto",
                        verbose = FALSE)
  forecast(hybrid, h = HORIZON)$mean
}

setCredentials("azure/credentials.json")

clust <- makeCluster("azure/cluster.json")
#clust <- getCluster("antarbatchclust", verbose = TRUE)

registerDoAzureParallel(clust)

num_nodes <- 25

azure_options <- list(
  chunksize = 1,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)


pkgs2load <- c("dplyr",
               "lubridate",
               "forecast",
               "forecastHybrid",
               "doParallel",
               "parallel")

setVerbose(TRUE)

forecasts <- foreach(ts_idx=1:NUM_TIME_SERIES,
                     .options.azure = azure_options,
                     .packages = pkgs2load) %dopar% {
                       
                        generate_forecast(ts_idx)
                       
                     }


