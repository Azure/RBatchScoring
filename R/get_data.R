library(bayesm)
library(dplyr)
library(tidyr)


print("Extracting data from bayesm package...")

data("orangeJuice")

dat <- orangeJuice$yx

dat <- dat %>% 
  select(-c(constant, profit)) %>%
  mutate(feat = as.integer(feat))

print("Cleaning data...")

# Removing discontinued stores/brands

dat <- dat %>%
  merge(
    dat %>%
      group_by(store, brand) %>%
      summarise(max_week = max(week)) %>%
      filter(max_week == 160) %>%
      select(store, brand),
    all.y = TRUE
  )


# Inserting records for missing time periods

get_stores_brands <- function(dat) {
  
  df <- dat %>%
    select(store, brand) %>%
    distinct()
  split(df, seq(nrow(df)))
}

insert_periods <- function(dat) {
  
  stores_brands <- get_stores_brands(dat)
  
  filled_dfs <- vector('list', length(stores_brands))
  
  for (i in 1:length(stores_brands)) {
    s <- stores_brands[[i]]$store
    b <- stores_brands[[i]]$brand
    df <- dat %>% filter(store == s, brand == b)
    weeks <- data.frame(week = min(df$week):max(df$week))
    weeks$store <- s
    weeks$brand <- b
    df <- df %>% merge(weeks, by = c('store', 'brand', 'week'), all.y = TRUE)
    filled_dfs[[i]] <- df
  }
  
  do.call(rbind, filled_dfs)
  
}

dat <- insert_periods(dat)

# Filling missing values

fill_time_series <- function(dat) {
  
  dat <- dat %>%
    group_by(store, brand) %>%
    arrange(week) %>%
    fill(-c(store, brand, week), .direction = "down") %>%
    ungroup()
  as.data.frame(dat)
}

dat <- fill_time_series(dat)

# Set first week to be 0

dat$week <- dat$week - min(dat$week)

dat$logsales <- dat$logmove
dat$logmove <- NULL

print("Saving data...")

# Save a lookup of stores and brands

write.csv(
  dat %>% select(store, brand) %>% distinct(),
  file = "lookup.csv",
  quote = FALSE,
  row.names = FALSE
)

# Split data into separate csv files

save_csv <- function(item) {
  s <- item$store
  b <- item$brand
  df <- dat %>% filter(store == s, brand == b)
  write.csv(df, file = file.path("data", paste0(s, "_", b, ".csv")), quote = FALSE, row.names = FALSE)
}

stores_brands <- get_stores_brands(dat)

lapply(stores_brands, save_csv)

print("Done")
