
library(dplyr)
library(forecast)
library(doAzureParallel)

source("R/utilities.R")

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()

file_dir <- "/mnt/batch/tasks/shared/files"

pkgs_to_load <- c("dplyr", "forecast")

lookup <- read.csv("lookup.csv")
segments <- split(lookup, seq(nrow(lookup)))


# Assign first 2 years to training data

test_start <- 102

# c(test_start %/% 52, test_start %% 52)

week2yearweek <- function(week) {c(week %/% 52, week %% 52)}

walk_forward_eval <- function(test_week, dat, segment) {
  
  train <- dat %>% filter(week < test_week)
  train <- df2list(segment, train, start = week2yearweek(min(train$week)))
  
  test <- dat %>% filter(week >= test_week, week <= test_week + 3)
  test <- df2list(segment, test, start = week2yearweek(min(test$week)))
  
  fit <- suppressWarnings(
    auto.arima(train$series)
  )
  
  pred <- as.numeric(forecast(fit, h = 4)$mean)
  actual <- as.numeric(test$series)
  list(pred, actual)
  
}

predict_segment <- function(idx, file_dir) {
  
  segment <- segments[[idx]]
  store <- segment$store
  brand <- segment$brand
  
  dat <- read.csv(file.path(file_dir, "data", paste0(store, "_", brand, ".csv")))

  lapply(test_start:max(dat$week) - 3, walk_forward_eval, dat, segment)
  
}

chunksize <- ceiling(length(segments) / 10)

azure_options <- list(
  chunksize = chunksize,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)


result <- foreach(idx=1:length(segments),
                  .options.azure = azure_options,
                  .packages = pkgs_to_load) %dopar% {
                   
                  predict_segment(idx, file_dir)
                    
                     
                  }

results <- do.call(c, result)

preds <- unlist(lapply(results, function(x) x[[1]][[1]]))
actuals <- unlist(lapply(results, function(x) x[[1]][[2]]))

eval_df <- data.frame(h = rep(1:4, length(results)/4),
                      pred = exp(preds),
                      actual = exp(actuals))


mean(abs(eval_df$pred - eval_df$actual) / eval_df$actual) # 0.0924

eval_df %>%
  group_by(h) %>%
  summarise(mape = mean(abs(pred - actual) / actual))
