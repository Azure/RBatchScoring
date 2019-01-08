load_data <- function(path = ".") {
  files <- lapply(list.files(path, full.names = TRUE), read.csv)
  dat <- do.call("rbind", files)
}


setenv <- function(name, value) {
  
  # Set R environment variable
  args <- list(value)
  names(args) <- name
  do.call(Sys.setenv, args)
  
  # Add variable to .env file
  txt <- paste(name, value, sep = "=")
  write(txt, file=".env", append=TRUE)
  
}


cleardotenv <- function() {
  system("> .env")
}


run <- function(cmd, ..., test = FALSE) {
  args <- list(...)
  print(do.call(sprintf, c(cmd, args)))
  if (!test) {
    system(
      do.call(sprintf, c(cmd, args))
    )
  }
}


create_features <- function(dat, step = 1, remove_target = TRUE) {
  lagged_features <- dat %>%
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
    ungroup()
  
  if (remove_target) {
    lagged_features$sales <- NULL
  }
  
  lagged_features %>%
    filter(complete.cases(.)) %>%
    group_by(product, sku, store) %>%
    mutate(level = cummean(lag1)) %>%
    ungroup() %>%
    select(-c(lag2, lag3, lag4, lag5))
}
