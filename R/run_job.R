
library(dplyr)
library(doAzureParallel)
library(jsonlite)

source("R/utilities.R")
source("R/create_credentials_json.R")
source("R/create_cluster_json.R")

create_credentials_json()
create_cluster_config(save_dir = ".")

setCredentials("credentials.json")
clust <- makeCluster("cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()

file_dir <- "/mnt/batch/tasks/shared/files"

pkgs_to_load <- c("dplyr", "gbm")

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