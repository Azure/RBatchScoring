create_features <- function(dat, step = 1, remove_target = TRUE) {
  
  # Computes features from product sales history including the most recent
  # observed value (lag1), the mean, max and min values of the previous
  # month, and the mean weekly sales by store (level).
  #
  # Args:
  #   dat:  dataframe containing historical sales values by sku and store.
  #   step: the time step to be forecasted. This determines how far the lagged
  #         features are shifted.
  #   remove_target: remove the target variable (sales) from the result.
  #
  # Returns:
  #   A dataframe of model features
  
  
  lagged_features <- dat %>%
    arrange(sku, store, week) %>%
    group_by(sku, store) %>%
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
    group_by(sku, store) %>%
    mutate(level = cummean(lag1)) %>%
    ungroup() %>%
    select(-c(lag2, lag3, lag4, lag5))
  
}
