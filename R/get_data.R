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


# Transform and rename variables

dat$sales <- exp(dat$logmove)
dat$logmove <- NULL

dat$product <- dat$brand
dat$sku <- dat$brand
dat$brand <- NULL

dat <- dat %>%
  select(
    product,
    sku,
    store,
    week,
    deal,
    feat,
    price1:price11,
    sales
  )


# Create data directories

dir.create("data")
dir.create(file.path("data", "training"))
dir.create(file.path("data", "scoring"))
dir.create(file.path("data", "scoring", "history"))
dir.create(file.path("data", "scoring", "futurex"))


# Save training data (reserve last 4 weeks for scoring)

train <- dat %>% filter(week <= max(dat$week) - 4)

write.csv(train, file = file.path("data", "training", "train.csv"),
          quote = FALSE, row.names = FALSE)


# Expand scoring data

print("Expanding scoring data...")

# Reserve the last 4 weeks for scoring, plus a further 8 weeks for lagged features

scoring <- dat %>% filter(week > max(dat$week) - 12)


# Replicate brands to ~40,000 skus (https://www.marketwatch.com/story/grocery-stores-carry-40000-more-items-than-they-did-in-the-1990s-2017-06-07)

multiplier <- floor(40000 / length(unique(dat$product)))

max_week <- max(scoring$week)

system.time({
  
  pb = txtProgressBar(min = 0, max = multiplier, initial = 0)
  
  for (m in 1:multiplier) {
    
    #if (m %% 100 == 0) print(paste("Generated", m, "of", multiplier, "products..."))
    setTxtProgressBar(pb, m)
    
    recent_history <- scoring %>%
      filter(week <= max_week - 4) %>%
      select(product, sku, store, week, sales) %>%
      mutate(product = m)
    
    write.csv(recent_history, file.path("data", "scoring", "history", paste0(m, ".csv")),
              quote = FALSE, row.names = FALSE)
    
    futurex <- scoring %>%
      filter(week > max_week - 4) %>%
      select(-sales) %>%
      mutate(product = m)
    
    write.csv(futurex, file.path("data", "scoring", "futurex", paste0(m, ".csv")),
              quote = FALSE, row.names = FALSE)
    
  }
  
})

print("Done")
