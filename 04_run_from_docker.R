
# 05_run_job_from_docker.R
# 
# This script defines a docker image for the job scheduler. The forecast
# generation process is then triggered from a docker container running locally.
#
# Note: it can take a few minutes for the cluster created in the previous script
# to be deleted. You will receive an error if you run this script while the
# previous cluster is being deleted. You can check the status of the cluster
# by checking the Pools pane of the Batch Account in the Azure Portal.
#
# Run time ~5 minutes on a 5 node cluster


# Define docker image ----------------------------------------------------------

# The dockerfile used to build to the scheduler docker image can be reviewed in
# docker/scheduler/dockerfile

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

library(dotenv)
source("R/utilities.R")


# Build scheduler docker image

run(
  "sudo docker build -t %s -f docker/scheduler/dockerfile .",
  get_env("SCHEDULER_CONTAINER_IMAGE")
)

run(
  "sudo docker tag %s:latest %s",
  get_env("SCHEDULER_CONTAINER_IMAGE"),
  get_env("SCHEDULER_CONTAINER_IMAGE")
)

run("sudo docker push %s", get_env("SCHEDULER_CONTAINER_IMAGE"))


# Run the docker container

env_vars <- get_env_var_list()

run(
  paste("sudo docker run", 
      paste0("-e ", env_vars, "=", get_env(env_vars), collapse = " "),
      get_env("SCHEDULER_CONTAINER_IMAGE")
  )
)
