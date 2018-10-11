

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
  series <- window(series, 1990)
  hybrid <- hybridModel(y = series,
                        weights = "equal",
                        errorMethod = "MAE",
                        models = MODELS,
                        lambda = "auto",
                        verbose = FALSE)
  forecast(hybrid, h = HORIZON)$mean
}

autoplot(generate_forecast(20))

# Create cluster ----------------------------------------------------------

setCredentials("azure/credentials.json")

RBATCH_SA_KEY <- system(
  sprintf('az storage account keys list -g %s --account-name %s --query "[0].value" | tr -d \'"\'', RBATCH_RG, RBATCH_SA),
  intern = TRUE
)

create_cluster_config()

#clust <- makeCluster("azure/cluster.json")
#clust <- getCluster("antarbatchclust", verbose = TRUE)

registerDoAzureParallel(clust)

# Check number of workers
getDoParWorkers()

# Run generate forecast on batch ------------------------------------------

setVerbose(TRUE)

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

system.time({
  
  forecasts <- foreach(ts_idx=1:NUM_TIME_SERIES,
                       .options.azure = azure_options,
                       .packages = pkgs2load) %dopar% {
    generate_forecast(ts_idx)                     }
  
})

autoplot(forecasts[[100]])



chunks <- split(1:NUM_TIME_SERIES, rep(1:num_nodes, each=NUM_TIME_SERIES/num_nodes))

system.time({
  
  forecasts <- foreach(node_idx=1:num_nodes,
                       .options.azure = azure_options,
                       .packages = pkgs2load) %dopar% {
                         
    cores <- detectCores()
    cl <- parallel::makeCluster(cores)
    registerDoParallel(cl)
    
    chunk <- chunks[[node_idx]]
    inner_results <- foreach(ts_idx = chunk[1]:chunk[length(chunk)],
                             .packages = pkgs2load) %dopar% {
      generate_forecast(ts_idx)
    }
    
    return(inner_results)
  
  }

})

getJobFile('job20181010133439', '19', 'stderr.txt')
getJobFile('job20181010133439', '19', 'stdout.txt')
getJobFile('job20181010133439', '24', '.txt')

forecasts <- unlist(forecasts, recursive = FALSE)

unlist(forecasts[[1]])

# Upload data to storage account ------------------------------------------


system(
  sprintf("az storage share create -n %s --account-name %s", RBATCH_SHARE, RBATCH_SA)
)

system(
  sprintf("az storage file upload --account-name %s --account-key %s --share-name %s --source \"./data/data.csv\" --path \"data.csv\"",
          RBATCH_SA,
          RBATCH_SA_KEY,
          RBATCH_SHARE)
)
# Create ACR/ACI/logic app ------------------------------------------------

stopCluster(clust)
