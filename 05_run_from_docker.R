
# 05_run_job_from_docker.R
# 
# This script defines a docker image for the job scheduler. The forecast
# generation process is then triggered from a docker container running locally.


# Enter resource settings ------------------------------------------------------

SCHEDULER_CONTAINER_IMAGE <- "" # e.g. <your-docker-id>/bfscheduler


# Define docker image ----------------------------------------------------------

library(dotenv)
source("R/utilities.R")

setenv("SCHEDULER_CONTAINER_IMAGE", SCHEDULER_CONTAINER_IMAGE)


# Review the scheduler docker image

file.edit(file.path("docker", "scheduler", "dockerfile"))


# Build scheduler docker image

run(
  "docker build -t %s -f docker/scheduler/dockerfile .",
  Sys.getenv("SCHEDULER_CONTAINER_IMAGE")
)

run(
  "docker tag %s:latest %s",
  Sys.getenv("SCHEDULER_CONTAINER_IMAGE"),
  Sys.getenv("SCHEDULER_CONTAINER_IMAGE")
)

run("docker push %s", Sys.getenv("SCHEDULER_CONTAINER_IMAGE"))


# Run the docker container

env_vars <- get_env_var_list()

run(
  paste("docker run", 
      paste0("-e ", env_vars, "=", Sys.getenv(env_vars), collapse = " "),
      Sys.getenv("SCHEDULER_CONTAINER_IMAGE")
  )
)
