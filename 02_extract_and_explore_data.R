
library(dotenv)
library(dplyr)
library(gbm)
library(tidyr)
library(AzureRMR)
library(AzureStor)
library(doAzureParallel)

source("R/utilities.R")
source("R/options.R")
source("R/get_data.R")


# Upload small datasets to file share

fs <- file_share(Sys.getenv("FILE_SHARE_URL"),
                 key = Sys.getenv("STORAGE_ACCOUNT_KEY"))

lapply(1:11, function(x) {
  fname <- paste0("product_", x, ".csv")
  upload_to_url(file.path("data", fname),
               file.path(Sys.getenv("FILE_SHARE_URL"), "data", "small", fname),
               key = Sys.getenv("STORAGE_ACCOUNT_KEY")
             )
})


# Register batch pool

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


# Tell nodes the mount location for data and forecasts directories

file_dir <- "/mnt/batch/tasks/shared/files"


# List of packages to load on each node

pkgs_to_load <- c("dplyr")


# Replicate brands to ~40,000 skus
multiplier <- floor(40000 / length(unique(dat$product)))

#chunksize <- ceiling(multiplier / as.integer(Sys.getenv("NUM_NODES")))

azure_options <- list(
  chunksize = 1,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)

num_nodes <- as.numeric(Sys.getenv("NUM_NODES"))
reps <- rep(1:num_nodes, each=multiplier/num_nodes)
reps <- c(reps, rep(max(reps), multiplier - length(reps)))
chunks <- split(1:multiplier, reps)

results <- foreach(chunk_idx=1:num_nodes,
                  .options.azure = azure_options,
                  .packages = pkgs_to_load) %dopar% {
                    
  # Read small data
  
  files <- lapply(list.files(file.path(file_dir, "data", "small"), full.names = TRUE), read.csv)
  dat <- do.call("rbind", files)
  
  max_week <- max(dat$week)
  
  
  # Expand data by replicating product data
  
  idx_list <- chunks[[chunk_idx]]
  
  lapply(idx_list, function(idx) {
    
    history <- dat %>%
            filter(week <= max_week - FORECAST_HORIZON) %>%
            select(product, sku, store, week, sales) %>%
            mutate(product = idx)
    
    futurex <- dat %>%
          filter(week > max_week - FORECAST_HORIZON) %>%
          select(-sales) %>%
          mutate(product = idx)
    
    write.csv(history,
              file.path(file_dir, "data", "large", "history",
                        paste0(idx, ".csv")),
              quote = FALSE, row.names = FALSE)
    
    write.csv(futurex,
              file.path(file_dir, "data", "large", "futurex",
                        paste0(idx, ".csv")),
              quote = FALSE, row.names = FALSE)
    
  })
  
  return(TRUE)
                    
}


# Generate forecasts for all SKUs of one product. First read in recent history
# sales history in order to generate lagged features

# recent_history <- read.csv(file.path("data", "history", "1.csv"))
#
# lag_var_names <- paste0("lag", 1:8)
#
# recent_history <- recent_history %>%
#   arrange(product, sku, store, desc(week)) %>%
#   mutate(var = rep(lag_var_names, nrow(.) / 8)) %>%
#   select(-week) %>%
#   spread(var, logsales)
#
#
# # Now read in regressors for the future forecast period
#
# futurex <- read.csv(file.path("data", "futurex", "1.csv")) %>%
#   arrange(product, sku, store, week)
#
#
# # Load trained gbm model
#
# gbmModel <- readRDS(file = "gbm")
#
# forecasts <- list()
#
# first_week <- min(futurex$week)
# score_weeks <- first_week:(first_week+3)
#
# # Recursively score future weeks and update lagged features
#
# for (i in 1:4) {
#
#   score_week <- score_weeks[i]
#
#   dat_score <- futurex %>% filter(week == score_week)
#
#   dat_score$pred <- predict(gbmModel, dat_score, n.trees = gbmModel$n.trees)
#
#   forecasts[[i]] <- dat_score
#
#   recent_history[ , paste0("lag", 2:8)] <- recent_history[ , paste0("lag", 1:7)]
#   recent_history$lag1 <- dat_score$pred
#
# }
#
# forecasts <- do.call(rbind, forecasts)
