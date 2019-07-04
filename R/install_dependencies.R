
# Install basic packages (from default cran mirror)

basic_pkgs <- c("devtools", "dotenv", "jsonlite")

install.packages(basic_pkgs)

repo <- "https://mran.microsoft.com/snapshot/2019-05-20"

pkgs <- c("bayesm", "dplyr", "tidyr", "ggplot2", "AzureStor", "AzureContainers", "AzureGraph")

install.packages(pkgs, repos = repo)

devtools::install_github(
  "Azure/rAzureBatch",
  ref = "6ca2bf7b1f4433a27531eaa86f0317499e9b4987" # 2018-08-09
)

devtools::install_github(
  "Azure/doAzureParallel",
  ref = "6d14d4522b1ff4218f19549b89dea6419a230a53" # 2018-11-26
)

devtools::install_github(
  "gbm-developers/gbm",
  ref = "b59270a787202d7ba2de5f2af7032854691d2b10"
)

devtools::install_github(
  "Azure/AzureRMR",
  ref = "7407db42d38bf6a52b291ce8f9c2e3e7d4c9163f" # 2019-05-23
)
