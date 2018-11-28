options(repos = "https://mran.microsoft.com/snapshot/2018-11-19")

pkgs <- c("bayesm", "dplyr", "tidyr", "forecast", "dotenv", "argparse", "jsonlite")
pkgs2install <- pkgs[!(pkgs %in% installed.packages()[,"Package"])]
if(length(pkgs2install)) install.packages(pkgs2install)

library(devtools)

devtools::install_github("Azure/rAzureBatch")
devtools::install_github("Azure/doAzureParallel")
