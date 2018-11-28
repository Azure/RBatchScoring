
library(dotenv)
library(dplyr)
library(doAzureParallel)

source("R/utilities.R")


# Build and upload the worker docker image to docker hub

run("docker build -t %s -f docker/worker/dockerfile .", Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker tag %s:latest %s", Sys.getenv("WORKER_CONTAINER_IMAGE"), Sys.getenv("WORKER_CONTAINER_IMAGE"))
run("docker push %s", Sys.getenv("WORKER_CONTAINER_IMAGE"))


# Register batch pool

setCredentials("azure/credentials.json")
clust <- makeCluster("azure/cluster.json")
registerDoAzureParallel(clust)
getDoParWorkers()


# Tell node the mount location for data and forecasts directories

file_dir <- "/mnt/batch/tasks/shared/files"


# List of packages to load on each node

pkgs_to_load <- c("dplyr", "forecast")


# Iterate over forecast 'segments' (store/brand combinations)

lookup <- read.csv("lookup.csv")
segments <- split(lookup, seq(nrow(lookup)))


# doAzureParallel job options

chunksize <- ceiling(length(segments) / as.integer(Sys.getenv("NUM_NODES")))

azure_options <- list(
  chunksize = chunksize,
  enableCloudCombine = TRUE,
  autoDeleteJob = FALSE
)


# Generate forecasts

result <- foreach(idx=1:length(segments),
                     .options.azure = azure_options,
                     .packages = pkgs_to_load) %dopar% {
                       
                       
  segment <- segments[[idx]]
  store <- segment$store
  brand <- segment$brand
  
  dat <- read.csv(file.path(file_dir, "data", paste0(store, "_", brand, ".csv")))
  dat <- dat %>% filter(week < 118)
  segment <- df2list(segment, dat)
  
  fit <- suppressWarnings(auto.arima(segment$series))
  pred <- forecast(fit, h = 4)
  result <- list(store = store, brand = brand, fcast = pred)
  
  res <- try(
    write.csv(data.frame(result$fcast), 
            file.path(file_dir, "forecasts", paste0(result$store, "_", result$brand, ".csv")),
            quote = FALSE)
  )
  success <- is.null(res)
  success
                       
}
