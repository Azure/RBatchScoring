# Specify the number of time series to forecast
NUM_TIME_SERIES <- 100

# Align all time series to finish on END PERIOD
END_PERIOD <- strptime("2019-12-01", "%Y-%m-%d")

# Date of first period of forecast
FORECAST_START <- strptime("2018-07-01", "%Y-%m-%d")

# Time series frequency (12 for monthly)
TS_FREQUENCY <- 12

# Forecast horizon
HORIZON <- 18

# Models to fit in hybridForecast
MODELS <- "aefs"

# Retrieve environment variables
RBATCH_RG <- Sys.getenv("RBATCH_RG")
RBATCH_SA <- Sys.getenv("RBATCH_SA")
RBATCH_SHARE <- Sys.getenv("RBATCH_SHARE")
RBATCH_CLUST <- Sys.getenv("RBATCH_CLUST")


