
# 04_run_from_docker.R
# 
# This script defines a docker image for the job scheduler. The forecast
# generation process is then triggered from a docker container running locally.
#
# Run time ~5 minutes on a 5 node cluster


# Define docker image ----------------------------------------------------------

# The dockerfile used to build to the scheduler docker image can be reviewed in
# docker/scheduler/dockerfile

library(dotenv)
library(AzureContainers)
source("R/utilities.R")

img_id <- paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE"))

# Build scheduler docker image

call_docker(sprintf("build -t %s -f docker/scheduler/dockerfile .", img_id))


# Tag the image

call_docker(sprintf("tag %s:latest %s", img_id, img_id))


# Push the image to Docker Hub

call_docker(sprintf("push %s", img_id))


# Run the docker container

env_vars <- get_dotenv_vars()

call_docker(paste("run", paste0("-e ", env_vars, "=", get_env(env_vars), collapse = " "), img_id))
