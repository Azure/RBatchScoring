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