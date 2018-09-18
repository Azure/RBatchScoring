
library(dplyr)
library(lubridate)
library(forecast)
library(opera)
library(ggplot2)
library(doParallel)

dat <- read.csv(file.path(".", "data", "data.csv"))

df_list <- split(dat, f = dat$ID)

df <- df_list[[1]]

end_period <- strptime("2019-12-01", "%Y-%m-%d")
df2ts <- function(df, test_period = 0) {
  start_period <- end_period %m-% months(nrow(df) - 1)
  train <- ts(df$Y[1:(nrow(df) - test_period)],
               start = c(year(start_period), month(start_period)),
               frequency = 12)
  series <- list(train)
  
  if (test_period) {
    test_start <- end_period %m-% months(test_period - 1)
    test <- ts(df$Y[(nrow(df) - test_period + 1):nrow(df)], 
               start = c(year(test_start), month(test_start)),
               frequency = 12)
    series[[2]] <- test
  }
  
  series
}


series <- df2ts(df, test_period = 18)
plot(ts(c(series[[1]], series[[2]])))

train <- series[[1]]
test <- series[[2]]

THETA <-forecast(thetaf(train), h = 18)
ARIMA <- forecast(auto.arima(train, lambda = "auto"), h = 18)
ETS <- forecast(ets(train), h = 18)
STL <- stlf(train, lambda = "auto", h = 18)

X <- cbind(THETA=THETA$mean, ETS=ETS$mean, ARIMA=ARIMA$mean, STL=STL$mean)

autoplot(cbind(train, X))
autoplot(X)

autoplot(cbind(test, X))

mape <- function(fcast, actual) {
  mean(abs(fcast - actual) / actual)
}

evaluate <- data.frame(
  cbind(
    mape(THETA$mean, test),
    mape(ETS$mean, test),
    mape(ARIMA$mean, test),
    mape(STL$mean, test)
  )
)
colnames(evaluate) <- c("THETA", "ETS", "ARIMA", "STL")
evaluate

MLpol0 <- mixture(model = "MLpol", loss.type = "square")
weights <- predict(MLpol0, X, test, type='weights')

head(weights)
tail(weights)

test_start <- strptime("2018-07-01", "%Y-%m-%d")
z <-ts(predict(MLpol0, X, test, type='response'), start=c(year(test_start), month(test_start)), frequency = 12)
Z <- cbind(test, X, z)
autoplot(Z)

evaluate$MLpol0 <- mape(z, test)
evaluate

# Forecast all series -----------------------------------------------------

generate_forecast <- function(df) {
  series <- df2ts(df)
  train <- series[[1]]
  
  THETA <-forecast(thetaf(train), h = 18)
  ARIMA <- forecast(auto.arima(train, lambda = "auto"), h = 18)
  ETS <- forecast(ets(train), h = 18)
  STL <- stlf(train, lambda = "auto", h = 18)

  MLpol0 <- mixture(model = "MLpol", loss.type = "square")

  X <- cbind(THETA=THETA$mean,
             ETS=ETS$mean, 
             ARIMA=ARIMA$mean, 
             STL=STL$mean)

  test_start <- strptime("2018-07-01", "%Y-%m-%d")
  fcast <-ts(predict(MLpol0, X, test, type='response'), 
             start=c(year(test_start), month(test_start)),
             frequency = 12)
  fcast
}

system.time(
  fcasts <- lapply(df_list[1:50], generate_forecast)
)


detectCores()

cores <- detectCores()
cl <- makeCluster(cores)
registerDoParallel(cl)
system.time({
  fcasts_par <- foreach(i = 1:50, .packages = c('lubridate', 'forecast', 'opera')) %dopar% {
    generate_forecast(df_list[[i]])
  }
})


# run on doAzureParallel --------------------------------------------------

library(doAzureParallel)
generateClusterConfig("cluster.json")
generateCredentialsConfig("credentials.json")
