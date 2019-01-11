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
