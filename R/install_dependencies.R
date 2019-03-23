
# Install basic packages (from default cran mirror)

basic_pkgs <- c("devtools", "dotenv", "jsonlite")

install.packages(basic_pkgs)

repo <- "https://mran.microsoft.com/snapshot/2019-01-07"

pkgs <- c("bayesm", "dplyr", "tidyr", "ggplot2")

install.packages(pkgs, repos = repo)

devtools::install_github(
  "cloudyr/AzureRMR",
  ref = "5b54604ca63e5e0154318f04cc1056f8f946fcde"
)

devtools::install_github(
  "cloudyr/AzureStor",
  ref = "f7886f2a7e5f0f26100060c94f88a8171ad54782"
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
