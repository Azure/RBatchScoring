
library(dotenv)
library(dplyr)
library(gbm)
library(tidyr)
library(ggplot2)
library(AzureRMR)
library(AzureStor)
library(doAzureParallel)

source("R/utilities.R")
source("R/options.R")


# Extract data and download models ----------------------------------------

# Extract data from bayesm package

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


# Download pre-trained forecasting models from blob storage

if (!dir.exists("models")) dir.create("models")

model_names <- expand.grid(1:7, c(0.5)) # c(0.05, 0.25, 0.5, 0.75, 0.95)
colnames(model_names) <- c("step", "quantile")
model_names$names <- paste0(
  "gbm_t", as.character(model_names$step),
  "_q",as.character(model_names$quantile * 100))
model_names <- model_names$names

download_model <- function(name) {
  download_from_url(
    file.path("https://batchforecastingpublic.blob.core.windows.net/batchforecastingpublic",
              name),
    file.path("models", name),
    overwrite = TRUE
  )
}

lapply(model_names, download_model)


# Use Az Copy to upload model files to file share

run("azcopy --source %s --destination %s --dest-key %s --quiet --recursive", "models",
    paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
    Sys.getenv("STORAGE_ACCOUNT_KEY"))



# Expand data on Batch ----------------------------------------------------

# Register batch pool

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


# Tell nodes the mount location for data and forecasts directories

file_dir <- "/mnt/batch/tasks/shared/files"


# List of packages to load on each node

pkgs_to_load <- c("dplyr")


# Replicate skus to ~40,000
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



# Explore data ------------------------------------------------------------


dat <- load_data("data")

dat %>%
  #mutate(sales = log(sales)) %>%
  group_by(week) %>%
  summarise(total_sales = sum(sales)) %>%
  ungroup() %>%
  ggplot(aes(x = week, y = total_sales)) +
  geom_line()

# dat %>%
#   mutate(sales = log(sales)) %>%
#   group_by(product, sku, week) %>%
#   summarise(sales = sum(sales)) %>%
#   ungroup() %>%
#   mutate(sku = as.factor(sku)) %>%
#   ggplot(aes(x = week, y = sales, colour = sku)) +
#   geom_line()
# 
# dat %>%
#   mutate(sales = log(sales)) %>%
#   group_by(product, store, week) %>%
#   summarise(sales = sum(sales)) %>%
#   ungroup() %>%
#   mutate(store = as.factor(store)) %>%
#   ggplot(aes(x = week, y = sales, colour = store)) +
#   geom_line()



# Generate a forecast -----------------------------------------------------

# Generate a forecast for one product

forecast_start <- max(dat$week) - FORECAST_HORIZON

create_features <- function(dat, step = 1) {
  dat %>%
    arrange(sku, store, week) %>%
    group_by(product, sku, store) %>%
    mutate(
      sales = log(sales),
      lag1 = lag(sales, n = 1 + step - 1),
      lag2 = lag(sales, n = 2 + step - 1),
      lag3 = lag(sales, n = 3 + step - 1),
      lag4 = lag(sales, n = 4 + step - 1),
      lag5 = lag(sales, n = 5 + step - 1),
      month_mean = (lag1 + lag2 + lag3 + lag4 + lag5) / 5,
      month_max = max(lag1, lag2, lag3, lag4, lag5, na.rm = TRUE),
      month_min = min(lag1, lag2, lag3, lag4, lag5, na.rm = TRUE)
    ) %>%
    ungroup() %>%
    filter(complete.cases(.)) %>%
    group_by(product, sku, store) %>%
    mutate(level = cummean(lag1)) %>%
    ungroup() %>%
    select(-c(lag2, lag3, lag4, lag5))
}


dat_product1 <- dat %>%
  filter(product == 1)

load_model <- function(name, path) {
  list(name = name, model = readRDS(file.path(path, name)))
}

models <- lapply(model_names, load_model, "models")

scored_dfs <- list()

for (step in 1:FORECAST_HORIZON) {
  score_dat <- create_features(dat_product1, step = step) %>%
    filter(week == forecast_start + step - 1)
  
  if (step <= 6) {
    model <- models[[step]]$model
  } else {
    model <- models[[7]]$model
  }
  score_dat$pred <- predict(model, score_dat, n.trees = model$n.trees)
  scored_dfs[[step]] <- score_dat
}

results <- do.call(rbind, scored_dfs)

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
