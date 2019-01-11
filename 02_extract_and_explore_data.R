
# 02_extract_and_explore_data.R
# 
# This script extracts the Orange Juice dataset from the bayesm package. The
# dataset consists of weekly sales for 11 SKUs of orange juice products across
# 83 stores. This script replicates these data to expand the number of products.
# The script also provides some exploration of the original dataset and
# generates a forecast using a set of pre-trained models.


library(dotenv)
library(dplyr)
library(gbm)
library(ggplot2)
library(AzureRMR)
library(AzureStor)
library(doAzureParallel)

source("R/utilities.R")
source("R/options.R")


# Extract data -----------------------------------------------------------------

# Extract and preprocess data from bayesm package

source("R/get_data.R")


# Expand data on Batch ----------------------------------------------------

# Register batch pool

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()
azure_options <- list(
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)


# Tell nodes the mount location for the file share

file_dir <- "/mnt/batch/tasks/shared/files"


# List of packages to load on each node

pkgs_to_load <- c("dplyr")


# Factor by which to replicate products

multiplier <- floor(TARGET_SKUS / length(unique(futurex$sku)))


# Split data replication operation equally across nodes

chunks <- chunk_by_nodes(multiplier)


# Only replicate sales value history (discard other features)

sales_history <- history %>% select(product, sku, store, week, sales)


# Replicate data

results <- foreach(
  
  idx=1:length(chunks),
  .options.azure = azure_options,
  .packages = pkgs_to_load,
  .noexport = c("history")
  
  ) %dopar% {
    
    products <- chunks[[idx]]
    
    lapply(products, function(product) {
      
      sales_history %>%
        mutate(product = product) %>%
        write.csv(
          file.path(file_dir, "data", "history",
                    paste0(product, ".csv")),
          quote = FALSE, row.names = FALSE
        )
      
      futurex %>%
        mutate(product = product) %>%
        write.csv(
          file.path(file_dir, "data", "futurex",
                    paste0(product, ".csv")),
          quote = FALSE, row.names = FALSE
        )
      
    })
    
    TRUE
    
}


# Explore data -----------------------------------------------------------------

dat <- load_data(file.path("data", "history"))


# Plot total sales

dat %>%
  group_by(week) %>%
  summarise(total_sales = sum(sales)) %>%
  ungroup() %>%
  ggplot(aes(x = week, y = total_sales)) +
  geom_line()


# Plot log sales of 5 SKUs

dat %>%
  filter(sku %in% 1:5) %>%
  mutate(sales = log(sales)) %>%
  group_by(product, sku, week) %>%
  summarise(sales = sum(sales)) %>%
  ungroup() %>%
  mutate(sku = as.factor(sku)) %>%
  ggplot(aes(x = week, y = sales, colour = sku)) +
  geom_line()


# Plot log of total sales in 5 stores

dat %>%
  filter(store %in% 1:5) %>%
  mutate(sales = log(sales)) %>%
  group_by(product, store, week) %>%
  summarise(sales = sum(sales)) %>%
  ungroup() %>%
  mutate(store = as.factor(store)) %>%
  ggplot(aes(x = week, y = sales, colour = store)) +
  geom_line()


# Generate a forecast ----------------------------------------------------------

# Generate a forecast for all 11 SKUs of one product


# Direct to local data directory

file_dir <- "."


# Load trained models

models <- load_models(path = "models")


# Define function for feature engineering

create_features <- function(dat, step = 1, remove_target = TRUE) {
  
  lagged_features <- dat %>%
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
    ungroup()
  
  if (remove_target) {
    lagged_features$sales <- NULL
  }
  
  lagged_features %>%
    filter(complete.cases(.)) %>%
    group_by(product, sku, store) %>%
    mutate(level = cummean(lag1)) %>%
    ungroup() %>%
    select(-c(lag2, lag3, lag4, lag5))
  
}


# Write function definition to file

write_function(create_features, "R/create_features.R")

# Define forecast scoring function

generate_forecast <- function(product,
                              models,
                              transform_predictions = TRUE) {
  
  
  # Read product sales history
  
  history <- read.csv(
    file.path(file_dir, "data", "history", paste0(product, ".csv"))
  ) %>%
    select(product, sku, store, week, sales)
  
  
  # Retain only the data needed to compute lagged features
  
  forecast_start_week <- max(history$week) + 1
  history <- history %>% filter(week >= forecast_start_week - NLAGS)
  
  
  # Read features for future time steps
  
  futurex <- read.csv(
    file.path(file_dir, "data", "futurex", paste0(product, ".csv"))
  )
  
  features <- bind_rows(futurex, history) 
  
  
  # Generate forecasts over the 13 steps of the forecast period
  
  steps <- 1:FORECAST_HORIZON
  
  generate_quantile_forecast <- function(q, model_idx, dat) {
    
    model_name <- paste0(
      "gbm_t", as.character(model_idx),
      "_q", as.character(100 * q)
    )
    model <- models[[model_name]]$model
    pred <- predict(model, dat, n.trees = model$n.trees)
    
    if (transform_predictions) pred <- exp(pred)
    
    pred
    
  }
  
  
  generate_step_forecasts <- function(step) {
    
    step_features <- create_features(features, step = step, remove_target = TRUE)
    step_features$step <- step
    
    if (step <= 6) model_idx <- step else model_idx <- 7
    
    quantile_forecasts <- lapply(
      QUANTILES,
      generate_quantile_forecast,
      model_idx,
      step_features
    )
    
    quantile_forecasts <- as.data.frame(quantile_forecasts)
    colnames(quantile_forecasts) <-  paste0("q", as.character(QUANTILES * 100))
    
    # Sort to avoid crossing quantiles
    
    t(apply(quantile_forecasts, 1, sort))
    
    cbind(step_features, quantile_forecasts)
    
  }
  
  step_forecasts <- lapply(steps, generate_step_forecasts)
  
  do.call(rbind, step_forecasts) %>% arrange(product, sku, store, week)
  
}


write_function(generate_forecast, "R/generate_forecast.R")


# Generate the forecasts

forecasts <- generate_forecast("1", models)


# Plot the forecast output for one SKU in one store

store10 <- 10
sku5 <- 5

history <- load_data(file.path("data", "history"))

history %>%
  filter(store == store10, sku == sku5, week >= 80) %>%
  select(week, sales) %>%
  bind_rows(
    forecasts %>%
      filter(sku == sku5, store == store10) %>%
      select(week, q5:q95)
  ) %>%
  ggplot(aes(x = week, y = q50)) +
  geom_line(colour = "red") +
  geom_linerange(aes(ymin = q25, ymax = q75), colour = "blue", size = 0.5) +
  geom_linerange(aes(ymin = q5, ymax = q95), colour = "royalblue1", size = 0.25) +
  geom_line(aes(x = week, y = sales))
