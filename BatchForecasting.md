Batch forecasting with R models
================

``` r
library(dotenv)
library(forecast)
library(forecastHybrid)
library(dplyr)
```

    ## 
    ## Attaching package: 'dplyr'

    ## The following objects are masked from 'package:stats':
    ## 
    ##     filter, lag

    ## The following objects are masked from 'package:base':
    ## 
    ##     intersect, setdiff, setequal, union

``` r
library(lubridate)
```

    ## 
    ## Attaching package: 'lubridate'

    ## The following object is masked from 'package:base':
    ## 
    ##     date

``` r
library(ggplot2)
library(tidyr)
library(jsonlite)
library(doParallel)
```

    ## Loading required package: foreach

    ## Loading required package: iterators

    ## Loading required package: parallel

``` r
library(doAzureParallel)
```

    ## 
    ## Attaching package: 'doAzureParallel'

    ## The following objects are masked from 'package:parallel':
    ## 
    ##     makeCluster, stopCluster

``` r
source("R/settings.R")
source("R/utilities.R")
source("R/create_cluster_config.R")
```

Get the data

``` r
source("R/get_data.R")
```

    ## [1] "Retrieving data from M4comp2018 package..."
    ## [1] "Writing data to ./data/data.csv ..."
    ## [1] "Finished"

Load an example time series

``` r
ts_list <- load_data("data")[1:NUM_TIME_SERIES]
ts_idx <- 50
df <- ts_list[[ts_idx]]
head(df)
```

    ##       ID T    Y
    ## 28385 50 1 7060
    ## 28386 50 2 7402
    ## 28387 50 3 7462
    ## 28388 50 4 7380
    ## 28389 50 5 6322
    ## 28390 50 6 6265

Split into a training and test period. Plot the training data.

``` r
series <- df2ts(df, test_period = HORIZON)
train <- series$train
test <- series$test
plot(train)
```

![](BatchForecasting_files/figure-markdown_github/unnamed-chunk-4-1.png)

Generate an equally weighted ensemble forecast

``` r
hybrid <- hybridModel(y = train,
                   weights = "equal",
                   errorMethod = "MAE",
                   models = MODELS,
                   lambda = "auto")
```

    ## Fitting the auto.arima model

    ## Fitting the ets model

    ## Fitting the thetam model

    ## Fitting the stlm model

``` r
evaluate_models(hybrid)
```

    ##              auto.arima       ets   thetam      stlm     comb
    ## Training set  0.8617953 0.8847966 7.854053 0.6888211 2.069529
    ## Test set      3.1503839 2.5787994 3.204213 2.3374044 2.811388

Plot all forecasts and actuals on test set

``` r
plot_forecasts(hybrid)
```

![](BatchForecasting_files/figure-markdown_github/unnamed-chunk-6-1.png)

Plot weighted ensemble forecast

``` r
plot(forecast(hybrid, h = HORIZON))
```

![](BatchForecasting_files/figure-markdown_github/unnamed-chunk-7-1.png)

Create and test a function to generate forecasts

``` r
generate_forecast <- function(ts_idx) {
  series <- df2ts(ts_list[[ts_idx]])$train
  hybrid <- hybridModel(y = series,
                        weights = "equal",
                        errorMethod = "MAE",
                        models = MODELS,
                        lambda = "auto",
                        verbose = FALSE)
  forecast(hybrid, h = HORIZON)$mean
}

autoplot(generate_forecast(20))
```

![](BatchForecasting_files/figure-markdown_github/unnamed-chunk-8-1.png)

Set credentials

``` r
RBATCH_SA_KEY <- system(
  sprintf('az storage account keys list -g %s --account-name %s --query "[0].value" | tr -d \'"\'', RBATCH_RG, RBATCH_SA),
  intern = TRUE
)
setCredentials("azure/credentials.json")
```

Create and register cluster

``` r
create_cluster_config()
clust <- makeCluster("azure/cluster.json")
```

    ## ===========================================================================
    ## Name: antarbatchclust
    ## Configuration:
    ##  Docker Image: angusrtaylor/batchforecasting
    ##  MaxTasksPerNode: 4
    ##  Node Size: Standard_D4s_v3
    ## Scale:
    ##  Autoscale Formula: QUEUE
    ##  Dedicated:
    ##      Min: 5
    ##      Max: 5
    ##  Low Priority:
    ##      Min: 0
    ##      Max: 0
    ## ===========================================================================
    ## The specified cluster 'antarbatchclust' already exists. Cluster 'antarbatchclust' will be used.
    ## Your cluster has been registered.
    ## Dedicated Node Count: 5
    ## Low Priority Node Count: 0

``` r
#clust <- getCluster("antarbatchclust", verbose = TRUE)
registerDoAzureParallel(clust)
```

Check number of workers

``` r
getDoParWorkers()
```

    ## [1] 20

Generate forecasts in parallel on Azure Batch

``` r
setVerbose(TRUE)

num_nodes <- 5

azure_options <- list(
  chunksize = 1,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)

pkgs2load <- c("dplyr",
              "lubridate",
              "forecast",
              "forecastHybrid",
              "doParallel",
              "parallel")


forecasts <- foreach(ts_idx=1:NUM_TIME_SERIES,
                     .options.azure = azure_options,
                     .packages = pkgs2load) %dopar% {
                       
                       generate_forecast(ts_idx)
                       
                       }
```

    ## ===========================================================================
    ## Id: job20181012132526
    ## chunkSize: 1
    ## enableCloudCombine: TRUE
    ## packages: 
    ##  dplyr; lubridate; forecast; forecastHybrid; doParallel; parallel; 
    ## errorHandling: stop
    ## wait: TRUE
    ## autoDeleteJob: FALSE
    ## ===========================================================================
    ## 
    Submitting tasks (1/50)
    Submitting tasks (2/50)
    Submitting tasks (3/50)
    Submitting tasks (4/50)
    Submitting tasks (5/50)
    Submitting tasks (6/50)
    Submitting tasks (7/50)
    Submitting tasks (8/50)
    Submitting tasks (9/50)
    Submitting tasks (10/50)
    Submitting tasks (11/50)
    Submitting tasks (12/50)
    Submitting tasks (13/50)
    Submitting tasks (14/50)
    Submitting tasks (15/50)
    Submitting tasks (16/50)
    Submitting tasks (17/50)
    Submitting tasks (18/50)
    Submitting tasks (19/50)
    Submitting tasks (20/50)
    Submitting tasks (21/50)
    Submitting tasks (22/50)
    Submitting tasks (23/50)
    Submitting tasks (24/50)
    Submitting tasks (25/50)
    Submitting tasks (26/50)
    Submitting tasks (27/50)
    Submitting tasks (28/50)
    Submitting tasks (29/50)
    Submitting tasks (30/50)
    Submitting tasks (31/50)
    Submitting tasks (32/50)
    Submitting tasks (33/50)
    Submitting tasks (34/50)
    Submitting tasks (35/50)
    Submitting tasks (36/50)
    Submitting tasks (37/50)
    Submitting tasks (38/50)
    Submitting tasks (39/50)
    Submitting tasks (40/50)
    Submitting tasks (41/50)
    Submitting tasks (42/50)
    Submitting tasks (43/50)
    Submitting tasks (44/50)
    Submitting tasks (45/50)
    Submitting tasks (46/50)
    Submitting tasks (47/50)
    Submitting tasks (48/50)
    Submitting tasks (49/50)
    Submitting tasks (50/50)
    ## Submitting merge task. . .
    ## Job Preparation Status: Package(s) being installed
    ## Waiting for tasks to complete. . .
    ## 
    | Progress: 0.00% (0/50) | Running: 0 | Queued: 47 | Completed: 0 | Failed: 0 |
    | Progress: 0.00% (0/50) | Running: 20 | Queued: 30 | Completed: 0 | Failed: 0 |
    | Progress: 22.00% (11/50) | Running: 20 | Queued: 19 | Completed: 11 | Failed: 0 |
    | Progress: 42.00% (21/50) | Running: 19 | Queued: 10 | Completed: 21 | Failed: 0 |
    | Progress: 56.00% (28/50) | Running: 19 | Queued: 3 | Completed: 28 | Failed: 0 |
    | Progress: 74.00% (37/50) | Running: 13 | Queued: 0 | Completed: 37 | Failed: 0 |
    | Progress: 82.00% (41/50) | Running: 9 | Queued: 0 | Completed: 41 | Failed: 0 |
    | Progress: 90.00% (45/50) | Running: 5 | Queued: 0 | Completed: 45 | Failed: 0 |
    | Progress: 94.00% (47/50) | Running: 3 | Queued: 0 | Completed: 47 | Failed: 0 |
    | Progress: 96.00% (48/50) | Running: 2 | Queued: 0 | Completed: 48 | Failed: 0 |
    | Progress: 96.00% (48/50) | Running: 2 | Queued: 0 | Completed: 48 | Failed: 0 |
    | Progress: 96.00% (48/50) | Running: 2 | Queued: 0 | Completed: 48 | Failed: 0 |
    | Progress: 98.00% (49/50) | Running: 1 | Queued: 0 | Completed: 49 | Failed: 0 |
    | Progress: 98.00% (49/50) | Running: 1 | Queued: 0 | Completed: 49 | Failed: 0 |
    | Progress: 98.00% (49/50) | Running: 1 | Queued: 0 | Completed: 49 | Failed: 0 |
    | Progress: 100.00% (50/50) | Running: 0 | Queued: 0 | Completed: 50 | Failed: 0 |
    ## Tasks have completed. Merging results Completed.

Plot a forecast

``` r
autoplot(forecasts[[50]])
```

![](BatchForecasting_files/figure-markdown_github/unnamed-chunk-13-1.png)
