load_data <- function(data_dir) {
  dat <- read.csv(file.path(data_dir, 'data.csv'))
  split(dat, f = dat$ID)
}

df2ts <- function(df, test_period = 0) {
  start_period <- END_PERIOD %m-% months(nrow(df) - 1)
  train <- ts(df$Y[1:(nrow(df) - test_period)],
              start = c(year(start_period), month(start_period)),
              frequency = 12)
  series <- list(train = train)
  
  if (test_period) {
    test_start <- END_PERIOD %m-% months(test_period - 1)
    test <- ts(df$Y[(nrow(df) - test_period + 1):nrow(df)], 
               start = c(year(test_start), month(test_start)),
               frequency = 12)
    series$test <- test
  }
  
  series
}

mape <- function(fcast, actual) {
  mean(abs(fcast - actual) / actual)
}

ts2date <- function(series) {
  round_date(as_date(date_decimal(unclass(time(series)))), unit="month")
}

evaluate_models <- function(model) {
  acc <- matrix(, nrow = 2, ncol = length(model$models) + 1, dimnames = list(c("Training set", "Test set"), c(model$models, "comb")))
  
  for (i in 1:length(model$models)) {
    acc[, i] <- accuracy(forecast(model[[model$models[i]]], h = 18), x = test)[, "MAPE"]
  }
  acc[, "comb"] <- accuracy(forecast(model, h = 18), x = test)[, "MAPE"]
  acc
}

plot_forecasts <- function(model) {
  
  forecasts <- do.call(rbind,
                       lapply(model$models,
                              function(m) {
                                data.frame(model=m,
                                           t=ts2date(test),
                                           fcast=as.numeric(forecast(model[[m]], h = HORIZON)$mean))
                              }))
  forecasts <- rbind(forecasts,
                     data.frame(model='combi',
                                t=ts2date(test),
                                fcast=as.numeric(forecast(model, h = HORIZON)$mean))
  )
  forecasts <- rbind(forecasts,
                     data.frame(model='actual',
                                t=ts2date(test),
                                fcast=as.numeric(test))
  )
  
  forecasts %>% ggplot(aes(x=t, y=fcast, colour=model, group=model)) + geom_line()
}