
library(dotenv)
library(dplyr)
library(RcppRoll)
library(doAzureParallel)
library(gbm)
library(caret)
library(AzureRMR)
library(AzureStor)

source("R/utilities.R")
source("R/options.R")

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


# Compute baselines -------------------------------------------------------

# Load small dataset

dat <- load_data("data")

# Define test period and validation period start

test_start <- 102


# Compute the mean forecast (mean of all previous values), as the baseline

mape <- function(forecasts, actuals) {mean(abs(forecasts - actuals) / actuals)}

baseline <- dat %>%
  select(sku, store, week, sales) %>%
  arrange(sku, store, week) %>%
  group_by(sku, store) %>%
  mutate(
    cum_mean = cummean(sales),
    mean_forecast = lag(cum_mean),
    lag1_forecast = lag(sales, n = 1),
    lag4_forecast = lag(sales, n = 4),
    lag8_forecast = lag(sales, n = 8),
    lag12_forecast = lag(sales, n = 12)
  ) %>%
  filter(week >= test_start) %>%
  ungroup() %>%
  filter(complete.cases(.)) %>%
  summarise(
    mean_forecast = mape(mean_forecast, sales),
    lag1_forecast = mape(lag1_forecast, sales),
    lag4_forecast = mape(lag4_forecast, sales),
    lag8_forecast = mape(lag8_forecast, sales),
    lag12_forecast = mape(lag12_forecast, sales)
  )

baseline

# Note that the performance of the lag12 forecast is about as poor as the
# mean forecast. Therefore the use of lagged features is unlikely to boost
# performance past a certain number of time steps.


# Tune t+1 model hyperparameters ----------------------------------------------

# Define feature engineering function

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


# Create dataset with lagged features. Log sales. Discard NAs.

dat_features <- create_features(dat)


# Split training and test sets

train <- dat_features %>% filter(week < test_start) %>% as.data.frame(.)
test <- dat_features %>% filter(week >= test_start) %>% as.data.frame(.)


# Specify training and validation fold indices

fold_weeks_in <- list(
  0:(test_start - (FORECAST_HORIZON * 3) - 1),
  0:(test_start - (FORECAST_HORIZON * 2) - 1),
  0:(test_start - FORECAST_HORIZON - 1)
)
fold_weeks_out <- list(
  (test_start - (FORECAST_HORIZON * 3)):(test_start - (FORECAST_HORIZON * 2) - 1),
  (test_start - (FORECAST_HORIZON * 2)):(test_start - FORECAST_HORIZON - 1),
  (test_start - FORECAST_HORIZON):(test_start - 1)
)

fold_idx_in <- list(
  as.integer(row.names(train[train$week %in% fold_weeks_in[[1]], ])),
  as.integer(row.names(train[train$week %in% fold_weeks_in[[2]], ])),
  as.integer(row.names(train[train$week %in% fold_weeks_in[[3]], ]))
)

fold_idx_out <- list(
  as.integer(row.names(train[train$week %in% fold_weeks_out[[1]], ])),
  as.integer(row.names(train[train$week %in% fold_weeks_out[[2]], ])),
  as.integer(row.names(train[train$week %in% fold_weeks_out[[3]], ]))
)


# Tune gbm hyperparameters

fit_control <- trainControl(
  method = "cv",
  index = fold_idx_in,
  indexOut = fold_idx_out,
  allowParallel = TRUE,
  savePredictions = FALSE,
  returnData = FALSE
)

# gbm_grid <-  expand.grid(
#   interaction.depth = c(5, 10, 15, 20),
#   n.trees = seq(500, 3000, 500),
#   shrinkage = c(0.01, 0.05, 0.1),
#   n.minobsinnode = c(10)
# )

gbm_grid <-  expand.grid(
  interaction.depth = c(15),
  n.trees = c(1000),
  shrinkage = c(0.01),
  n.minobsinnode = c(10)
)

form <- as.formula(
  paste("sales ~ sku + deal + feat + level +",
        "month_mean + month_max + month_min + lag1 +",
        paste(paste0("price", 1:11), collapse = " + ")
  )
)

system.time({
  gbm_fit <- train(form,
                  data = train,
                  method = "gbm",
                  distribution = "gaussian",
                  tuneGrid = gbm_grid,
                  trControl = fit_control, 
                  verbose = FALSE)
})


# Inspect the tuning results

param_results <- gbm_fit$results %>% arrange(RMSE)
View(param_results)


# Retrieve the best parameter set

N.TREES <- gbm_fit$bestTune$n.trees
INTERACTION.DEPTH <- gbm_fit$bestTune$interaction.depth
SHRINKAGE <- gbm_fit$bestTune$shrinkage
N.MINOBSINNODE <- gbm_fit$bestTune$n.minobsinnode
gbm_fit$bestTune


# Evaluate the final model on test set

mape(exp(predict(gbm_fit, test, n.trees = gbm_fit$n.trees)), exp(test$sales))

m <- gbm_fit$finalModel
m$data <- NULL
saveRDS(m, "model")
# Plot variable importance

plot(varImp(gbm_fit))


# Find lagged feature relevance at different future time steps ------------

pkgs_to_load <- c("dplyr", "gbm")

vars_noexport <- c("dat", "dat_features", "train", "test", "gbm_fit")

file_dir <- "/mnt/batch/tasks/shared/files"

azure_options <- list(
  chunksize = 1,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)

# models <- foreach(step=1:FORECAST_HORIZON,
#                   .options.azure = azure_options,
#                   .packages = pkgs_to_load,
#                   .noexport = vars_noexport) %dopar% {
#                     
#    dat <- load_data(file.path(file_dir, "data", "small"))
#    
#    dat <- create_features(dat, step = step)
#   
#    train <- dat %>% filter(week < test_start) %>% as.data.frame(.)
#    test <- dat %>% filter(week >= test_start) %>% as.data.frame(.)
#    
#    model <- gbm(
#      form,
#      distribution = "gaussian",
#      data = train,
#      n.trees = N.TREES,
#      interaction.depth = INTERACTION.DEPTH,
#      n.minobsinnode = N.MINOBSINNODE,
#      shrinkage = SHRINKAGE,
#      keep.data = FALSE
#    )
#    
#    perf <- mape(exp(predict(model, test, n.trees = model$n.trees)), exp(test$sales))
#    
#    list(model = model, perf = perf)
#    
#                   }
# 
# plot(print(unlist(lapply(models, function(m) m$perf))),
#      xlab = "time step", ylab = "MAPE")
# 
# rm(models)
# gc()


# Train final models ------------------------------------------------------

# Train a single model per time step for steps 1 to 6. Then train one model
# for all subsequent time steps (without lagged features).

# Also train models for quantiles 0.95, 0.75, 0.5, 0.25, 0.05

required_models <- expand.grid(1:7, c(0.5)) # c(0.05, 0.25, 0.5, 0.75, 0.95)
colnames(required_models) <- c("step", "quantile")
required_models <- split(required_models, seq(nrow(required_models)))

lagged_feature_steps <- 6

time_step_models <- foreach(idx=1:length(required_models),
                  .options.azure = azure_options,
                  .packages = pkgs_to_load,
                  .noexport = vars_noexport) %dopar% {
                    
    step <- required_models[[idx]]$step
    quantile <- required_models[[idx]]$quantile
                    
    dat <- load_data(file.path(file_dir, "data", "small"))
    
    dat <- create_features(dat, step = step)
    
    train <- dat %>% filter(week < test_start) %>% as.data.frame(.)
    test <- dat %>% filter(week >= test_start) %>% as.data.frame(.)
    
    if (step <= lagged_feature_steps) {
      form <- as.formula(
        paste("sales ~ sku + deal + feat + level +",
              "month_mean + month_max + month_min + lag1 +",
              paste(paste0("price", 1:11), collapse = " + ")
        )
      )
        
    } else {
      form <- as.formula(
        paste("sales ~ sku + deal + feat + level +",
              paste(paste0("price", 1:11), collapse = " + ")
              )
      )
    }
    
    model <- gbm(
      form,
      distribution = "gaussian",
      data = train,
      n.trees = N.TREES,
      interaction.depth = INTERACTION.DEPTH,
      n.minobsinnode = N.MINOBSINNODE,
      shrinkage = SHRINKAGE,
      keep.data = FALSE
    )
    
    perf <- mape(exp(predict(model, test, n.trees = model$n.trees)), exp(test$sales))
    
    model$data <- NULL
    
    name <- paste0("gbm_t", as.character(step), "_q", as.character(quantile * 100))
    saveRDS(model, file = file.path(file_dir, "models", name))
    
    list(step = step, quantile = quantile, model = model, perf = perf)
    
  }


# Overwrite model files locally

save_model <- function(m) {
  quantile <- as.character(m$quantile * 100)
  step <- as.character(m$step)
  name <- paste0("gbm_t", step, "_q", quantile)
  saveRDS(m$model, file = file.path("models", name))
}

lapply(time_step_models, save_model)

save_model(time_step_models[[1]])


# Use Az Copy to upload model files to file share

run("azcopy --source %s --destination %s --dest-key %s --quiet --recursive", "models",
    paste0(Sys.getenv("FILE_SHARE_URL"), "models"),
    Sys.getenv("STORAGE_ACCOUNT_KEY"))
