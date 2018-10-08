

# Prerequisites -----------------------------------------------------------

# Installed R, RStudio, AZCLI, R packages (or pulled docker container)
# Run doAzureParallel setup script
# Saved output in credentials.json
# Completed template.env
# Open this file (possibly in docker container)


# Import libraries and settings -------------------------------------------

library(dotenv)
library(forecast)
library(forecastHybrid)
library(dplyr)
library(lubridate)
library(ggplot2)
library(tidyr)
library(jsonlite)
library(doParallel)
library(doAzureParallel)
source("R/settings.R")
source("R/utilities.R")
source("R/create_cluster_config.R")

# Get the data ------------------------------------------------------------

source("R/get_data.R")

# Forecast example -------------------------------------------------------

# load an example time series
ts_idx <- 25
df_list <- load_data("data")
df <- df_list[[ts_idx]]
head(df)

# split into a training and test period
series <- df2ts(df, test_period = HORIZON)
train <- series$train
test <- series$test

plot(train)

# generate an equally weighted combination forecast
hybrid <- hybridModel(y = train,
                   weights = "equal",
                   errorMethod = "MAE",
                   models = MODELS,
                   lambda = "auto")


evaluate_models(hybrid)

plot(forecast(hybrid, h = HORIZON))

plot_forecasts(hybrid)


# Forecast function -------------------------------------------------------

series_list <- load_data("data")[1:NUM_TIME_SERIES]

generate_forecast <- function(ts_idx) {
  series <- df2ts(series_list[[ts_idx]])$train
  hybrid <- hybridModel(y = series,
                        weights = "equal",
                        errorMethod = "MAE",
                        models = MODELS,
                        lambda = "auto",
                        verbose = FALSE)
  forecast(hybrid, h = HORIZON)$mean
}

autoplot(generate_forecast(20))


# Upload data to storage account ------------------------------------------

system(
  sprintf("az storage file upload -s resources --source R/mnist_cnn.R --path R --account-name %s",
          RBATCH_SA)
)

RBATCH_SA_KEY <- system(
  sprintf('az storage account keys list -g %s --account-name %s --query "[0].value" | tr -d \'"\'', RBATCH_RG, RBATCH_SA),
  intern = TRUE
)

system(
  sprintf("az storage share create -n %s --account-name %s", RBATCH_SHARE, RBATCH_SA)
)

system(
  sprintf("az storage file upload --account-name %s --account-key %s --share-name %s --source \"./data/data.csv\" --path \"data.csv\"",
          RBATCH_SA,
          RBATCH_SA_KEY,
          RBATCH_SHARE)
)

# Create cluster ----------------------------------------------------------

setCredentials("azure/credentials.json")

create_cluster_config()

clust <- makeCluster("azure/cluster.json")

registerDoAzureParallel(clust)

# Check number of workers
getDoParWorkers()

# Run generate forecast on batch ------------------------------------------

num_nodes <- 25

chunks <- split(1:NUM_TIME_SERIES, 1:25)

azure_options <- list(
  chunksize = 1,
  enableCloudCombine = TRUE
)

pkgs2load <- c("dplyr",
              "lubridate",
              "forecast",
              "forecastHybrid",
              "doParallel",
              "parallel")
system.time({
  
  forecasts <- foreach(ts_idx=1:NUM_TIME_SERIES,
                       .options.azure = azure_options,
                       .packages = pkgs2load) %dopar% {
    generate_forecast(ts_idx)
                       }
  
})

autoplot(forecasts[[1]])


forecasts <- foreach(node_idx=1:num_nodes,
                     .options.azure = azure_options,
                     .packages = pkgs2load) %dopar% {
  cores <- detectCores()
  print(cores)
  cl <- parallel::makeCluster(cores)
  registerDoParallel(cl)
  
  inner_results <- foreach(ts_idx = chunks[[node_idx]],
                           .packages = pkgs2load) %dopar% {
    generate_forecast(ts_idx)
  }
  
  inner_results

}

forecasts <- unlist(forecasts, recursive = FALSE)

unlist(forecasts[[1]])

# Create ACR/ACI/logic app ------------------------------------------------



