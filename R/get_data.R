
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(M4comp2018))
suppressPackageStartupMessages(library(lubridate))

print("Retrieving data from M4comp2018 package...")
data("M4")

monthly_industry <- Filter(function(l) (l$period == "Monthly") & (l$type == "Industry"), M4)

series2df <- function(series) {
  data.frame(T=1:(series$n + 18), Y=unclass(c(series$x, series$xx)))
}

df_list <- lapply(monthly_industry, series2df)

df_all <- bind_rows(df_list, .id = "ID")

filepath <- file.path(".", "data", "data.csv")
print(paste("Writing data to", filepath, "..."))

write.csv(df_all, filepath, row.names = FALSE)

print("Finished")

# # Align all time series such that they end in Dec 2019
# new_end_period <- strptime("2019-12-01", "%Y-%m-%d")
# 
# series <- monthly_industry[[1]]
# df <- data.frame(T=1:(series$n + 18), Y=unclass(c(series$x, series$xx)))
# 
# 
# align_series <- function (series) {
#   len_test_period <- 18
#   new_start_period <- new_end_period %m-% months(series$n + len_test_period - 1)
#   start_year <- year(new_start_period)
#   start_month <- month(new_start_period)
#   ts(c(series$x, series$xx), start = c(start_year, start_month), frequency = 12)
# }
# 
# series_list <- lapply(monthly_industry, realign_series)
# 
# series2df <- function(series) {
#   data.frame(T=unclass(time(series)), Y=unclass(series))
# }
# 
# df_list <- lapply(series_list, series2df)
