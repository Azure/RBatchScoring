
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
source("R/utilities.R")


# Build scheduler docker image

run(
  "sudo docker build -t %s -f docker/scheduler/dockerfile .",
  paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE"))
)


# Tag the image

run(
  "sudo docker tag %s:latest %s",
  paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE")),
  paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE"))
)


# Push the image to Docker Hub

run("sudo docker push %s",
    paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE"))
)


# Run the docker container

env_vars <- get_dotenv_vars()

run(
  paste("sudo docker run", 
      paste0("-e ", env_vars, "=", get_env(env_vars), collapse = " "),
      paste0(get_env("DOCKER_ID"), "/", get_env("SCHEDULER_CONTAINER_IMAGE"))
  )
)
