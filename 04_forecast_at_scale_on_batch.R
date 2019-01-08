
library(dotenv)
library(dplyr)
library(doAzureParallel)
library(gbm)

source("R/utilities.R")
source("R/options.R")

forecast_start_week <- 120 - FORECAST_HORIZON + 1
NLAGS <- 5

model_names <- expand.grid(1:7, c(0.5)) # c(0.05, 0.25, 0.5, 0.75, 0.95)
colnames(model_names) <- c("step", "quantile")
model_names$names <- paste0(
  "gbm_t", as.character(model_names$step),
  "_q",as.character(model_names$quantile * 100))
model_names <- model_names$names

# Register batch pool

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


# Tell node the mount location for data and forecasts directories

file_dir <- "/mnt/batch/tasks/shared/files"
#file_dir <- "../bffs/"


# List of packages to load on each node

pkgs_to_load <- c("dplyr", "gbm")


# doAzureParallel job options

# chunksize <- ceiling(3636 / as.integer(Sys.getenv("NUM_NODES")))
chunksize <- 1

num_nodes <- as.numeric(Sys.getenv("NUM_NODES"))
reps <- rep(1:num_nodes, each=3636/num_nodes)
reps <- c(reps, rep(max(reps), 3636 - length(reps)))
chunks <- split(1:3636, reps)

azure_options <- list(
  chunksize = chunksize,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)

load_model <- function(name, path) {
  list(name = name, model = readRDS(file.path(path, name)))
}


# Generate forecasts

system.time({
result <- foreach(idx=1:length(chunks),
                     .options.azure = azure_options,
                     .packages = pkgs_to_load) %dopar% {
                       
  models <- lapply(model_names, load_model, file.path(file_dir, "models"))
  
  products <- chunks[[idx]]
  
  for (product in products) {
    
    history <- read.csv(file.path(file_dir, "data", "large", "history",
                                  paste0(product, ".csv"))) %>%
      filter(week >= forecast_start_week - NLAGS)
    
    futurex <- read.csv(file.path(file_dir, "data", "large", "futurex",
                                  paste0(product, ".csv")))
    
    features <- bind_rows(futurex, history) 
    
    steps <- 1:13
    
    forecasts <- lapply(steps, function(step) {
      
      step_features <- create_features(features, step = step)
      step_features$step <- step
      
      if (step <= 6) {
        model <- models[[step]]$model
      } else {
        model <- models[[7]]$model
      }
      
      step_features$pred <- predict(model, step_features, n.trees = model$n.trees)
      step_features
      
    })
    forecasts <- do.call(rbind, forecasts) %>% arrange(product, sku, store, week)
    write.csv(forecasts, 
            file.path(file_dir, "data", "large", "forecasts",
                      paste0(product, ".csv")),
            quote = FALSE, row.names = FALSE)
    
  }
                       
  
  return(TRUE)
                       
                     }
})
