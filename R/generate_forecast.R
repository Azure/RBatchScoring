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
