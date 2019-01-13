
# 01_generate_forecasts_locally.R
# 
# This script extracts product sales data from the bayesm R package. The data
# consists of weekly sales of 11 orange juice brands across 83 stores. This
# script generates forecasts for these products using pre-trained models.
#
# Run time ~1 minute


library(dplyr)
library(gbm)
library(ggplot2)

source("R/utilities.R")
source("R/options.R")


# Extract data -----------------------------------------------------------------

# Extract and preprocess data from bayesm package

source("R/get_data.R")


# Explore data -----------------------------------------------------------------

dat <- read.csv(file.path("data", "history", "product1.csv"))


# Plot quantiles of total sales by stores.

dat %>%
  group_by(week, store) %>%
  summarise(sales = sum(sales)) %>%
  group_by(week) %>%
  summarise(
    q5 = quantile(sales, probs = 0.05),
    q25 = quantile(sales, probs = 0.25),
    q50 = quantile(sales, probs = 0.5),
    q75 = quantile(sales, probs = 0.75),
    q95 = quantile(sales, probs = 0.95)
  ) %>%
  ggplot(aes(x = week)) +
  geom_ribbon(aes(ymin = q5, ymax = q95, fill = "5%-95%"), alpha = .25) + 
  geom_ribbon(aes(ymin = q25, ymax = q75, fill = "25%-75%"), alpha = .25) +
  geom_line(aes(y = q50, colour = "q50")) +
  scale_fill_manual(name = "", values = c("25%-75%" = "red", "5%-95%" = "blue")) +
  scale_colour_manual(name = "", values = c("q50" = "black")) +
  labs(y = "total sales by store") +
  ggtitle("Quantiles of total sales by store")


# Plot mean weekly log sales by SKU

dat %>%
  mutate(
    sku = as.factor(sku),
    sales = log(sales)
  ) %>%
  group_by(sku, week) %>%
  summarise(mean_sales = sum(sales)) %>%
  ggplot(aes(x = sku, y = mean_sales, colour = sku)) +
  geom_boxplot() +
  labs(y = "mean weekly log sales") +
  ggtitle("Mean weekly log sales by SKU")


# Generate a forecast ----------------------------------------------------------

# Download pre-trained models from blob storage. We are forecasting 13 time
# steps (weeks) into the future and generating predictions for 5 quantiles
# (5%, 25%, 50%, 75% and 95%). A separate model has been trained for each time
# step and quantile combination for time steps 1 to 6. For time steps 7 to 13, a
# single model per quantile has been trained. There are 35 individual models
# in total.

create_dir("models")

run(
  "azcopy --source %s --destination %s --quiet --recursive",
  file.path(
    "https://happypathspublic.blob.core.windows.net",
    "assets",
    "batch_forecasting"
  ),
  "models"
)


# List the downloaded models. Note that models for t7 (time step 7) will be
# applied to all time steps from 7 to 13.

list.files("models")


# Load trained models

models <- load_models(path = "models")


# Define function for creating model features

create_features <- function(dat, step = 1, remove_target = TRUE) {
  
  # Computes features from product sales history including the most recent
  # observed value (lag1), the mean, max and min values of the previous
  # month, and the mean weekly sales by store (level).
  #
  # Args:
  #   dat:  dataframe containing historical sales values by sku and store.
  #   step: the time step to be forecasted. This determines how far the lagged
  #         features are shifted.
  #   remove_target: remove the target variable (sales) from the result.
  #
  # Returns:
  #   A dataframe of model features
  
  
  lagged_features <- dat %>%
    arrange(sku, store, week) %>%
    group_by(sku, store) %>%
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
    group_by(sku, store) %>%
    mutate(level = cummean(lag1)) %>%
    ungroup() %>%
    select(-c(lag2, lag3, lag4, lag5))
  
}


# Write function definition to file

write_function(create_features, "R/create_features.R")




# Define forecast scoring function

generate_forecast <- function(product,
                              models,
                              file_dir = ".",
                              transform_predictions = TRUE) {
  
  # Generates quantile forecasts with a horizon of 13 weeks for each sku of
  # a product.
  #
  # Args:
  #   product: the product ID
  #   models: a list of trained gbm models for each time step and quantile
  #   file_dir: relative or absolute path to the directory where data are stored
  #   transform_predictions: transform the forecast from log sales to sales
  #
  # Returns:
  #   A dataframe of quantile forecasts
  
  
  # Read product sales history
  
  history <- read.csv(
    file.path(file_dir, "data", "history",
              paste0("product", product, ".csv"))
    ) %>%
    select(sku, store, week, sales)
  
  
  # Retain only the data needed to compute lagged features
  
  forecast_start_week <- max(history$week) + 1
  history <- history %>% filter(week >= forecast_start_week - NLAGS)
  
  
  # Read features for future time steps
  
  futurex <- read.csv(
    file.path(file_dir, "data", "futurex",
              paste0("product", product, ".csv"))
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
  
  do.call(rbind, step_forecasts) %>% arrange(sku, store, week)
  
}


write_function(generate_forecast, "R/generate_forecast.R")


# Generate a forecast for all 11 SKUs of product 1

forecasts <- generate_forecast("1", models)


# Plot the forecast output for one SKU in one store

store10 <- 10
sku5 <- 5

history %>%
  filter(store == store10, sku == sku5, week >= 80) %>%
  select(week, sales) %>%
  bind_rows(
    forecasts %>%
      filter(sku == sku5, store == store10) %>%
      select(week, q5:q95)
  ) %>%
  ggplot(aes(x = week)) +
  geom_ribbon(aes(ymin = q5, ymax = q95, fill = "5%-95%"), alpha = .25) + 
  geom_ribbon(aes(ymin = q25, ymax = q75, fill = "25%-75%"), alpha = .25) +
  geom_line(aes(y = q50, colour = "q50")) +
  geom_line(aes(x = week, y = sales)) +
  scale_fill_manual(name = "", values = c("25%-75%" = "red", "5%-95%" = "blue")) +
  scale_colour_manual(name = "", values = c("q50" = "black")) +
  labs(y = "sales") +
  ggtitle(paste("Forecast for product 1, sku", sku5, "in store", store10))

