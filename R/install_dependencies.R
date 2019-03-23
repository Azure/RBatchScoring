
# Install basic packages (from default cran mirror)

basic_pkgs <- c("devtools", "dotenv", "jsonlite")

install.packages(basic_pkgs)

repo <- "https://mran.microsoft.com/snapshot/2019-01-07"

pkgs <- c("bayesm", "dplyr", "tidyr", "ggplot2")

install.packages(pkgs, repos = repo)

devtools::install_github(
  "cloudyr/AzureAuth",
  ref = "e638802cd588bd90d6d090dbe0b974493bbb6f27" # 2019-03-22
)

devtools::install_github(
  "cloudyr/AzureRMR",
  ref = "5eeb60988a2079b6b320af8df306c4fad802c13c" # 2019-03-23
)

devtools::install_github(
  "cloudyr/AzureStor",
  ref = "79d0c80ff151ec5efc44a8133b465aa0fc0daabe" # 2019-03-21
)

devtools::install_github(
  "Azure/rAzureBatch",
  ref = "1ab39ca1bb8ae589a6f5c80f5d91c1ee79b1ee8a" # 2019-28-14
)

devtools::install_github(
  "Azure/doAzureParallel",
  ref = "975858072e8194d465a1f63262e35815ebbf0306" # 2019-02-14
)

devtools::install_github(
  "gbm-developers/gbm",
  ref = "b59270a787202d7ba2de5f2af7032854691d2b10"
)
