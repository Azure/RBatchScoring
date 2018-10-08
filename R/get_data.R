
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

rm(df_all, df_list, M4, monthly_industry, filepath, series2df)

print("Finished")

