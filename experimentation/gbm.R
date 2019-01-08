
library(dplyr)
library(doAzureParallel)
library(gbm)
library(caret)

source("R/utilities.R")

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


pkgs_to_load <- c("dplyr", "caret")

files <- lapply(list.files("data", full.names = TRUE), read.csv)
dat <- do.call("rbind", files)

dat$logsales <- log(dat$sales)
dat$sales <- NULL

# create lagged features

dat <- dat %>%
  group_by(product, sku, store) %>%
  mutate(
    lag1 = lag(logsales),
    lag2 = lag(logsales, n = 2),
    lag3 = lag(logsales, n = 3),
    lag4 = lag(logsales, n = 4),
    lag5 = lag(logsales, n = 5),
    lag6 = lag(logsales, n = 6),
    lag7 = lag(logsales, n = 7),
    lag8 = lag(logsales, n = 8)
  )

dat <- dat[complete.cases(dat), ]

test_start <- 102

train <- dat %>% filter(week < test_start) %>% as.data.frame()

valid_start <- max(dat$week) - (max(dat$week) - test_start) * 2

idx <- list(as.integer(row.names(train[train$week < valid_start, ])))

idxOut <- list(as.integer(row.names(train[train$week >= valid_start, ])))

test <- dat %>% filter(week > test_start)
train$product <- NULL
train$week <- NULL
test$product <- NULL
test$week <- NULL

fitControl <- trainControl(
  method = "cv",
  index = idx,
  indexOut = idxOut,
  allowParallel = TRUE,
  savePredictions = FALSE
  )

gbmGrid <-  expand.grid(
  interaction.depth = c(5, 10, 15, 20),
  n.trees = seq(100, 2000, 200),
  shrinkage = c(0.005, 0.01, 0.05, 0.1),
  n.minobsinnode = c(10)
)

gbmFit <- train(logsales ~ ., data = train, 
                 method = "gbm",
                 distribution = "gaussian",
                 tuneGrid = gbmGrid,
                 trControl = fitControl, 
                 verbose = FALSE)

param_results <- gbmFit$results

param_results <- param_results %>% arrange(RMSE)

gbmFit$bestTune
# n.trees interaction.depth shrinkage n.minobsinnode
# 110    1900                15      0.05             10

gbmModel <- gbmFit$finalModel
gbmModel$data <- NULL
saveRDS(gbmModel, file = "gbm")


#gbmModel <- readRDS(file = "gbm")

test$pred <- predict(gbmModel, test, n.trees = gbmModel$n.trees)
mean(abs(exp(test$pred) - exp(test$logsales)) / exp(test$logsales)) # 0.4

varImp(gbmFit)

ggplot(gbmFit)
