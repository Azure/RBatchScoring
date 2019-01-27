chunk_by_nodes <- function(multiplier) {
  
  num_nodes <- as.numeric(Sys.getenv("NUM_NODES"))
  reps <- rep(1:num_nodes, each=multiplier/num_nodes)
  reps <- c(reps, rep(max(reps), multiplier - length(reps)))
  chunks <- split(1:multiplier, reps)
  chunks
  
}


create_dir <- function(path) if (!dir.exists(path)) dir.create(path)


load_data <- function(path = ".") {
  files <- lapply(list.files(path, full.names = TRUE), read.csv)
  dat <- do.call("rbind", files)
}


list_required_models <- function(lagged_feature_steps, quantiles) {
  required_models <- expand.grid(1:(lagged_feature_steps + 1), quantiles)
  colnames(required_models) <- c("step", "quantile")
  split(required_models, seq(nrow(required_models)))
}


list_model_names <- function(required_models) {
  lapply(
    required_models,
    function(model) {
      paste0(
        "gbm_t", as.character(model$step), "_q",
        as.character(model$quantile * 100)
      )
    }
  )
}


setenv <- function(name, value) {
  
  # Set R environment variable
  args <- list(value)
  names(args) <- name
  do.call(Sys.setenv, args)
  
  # Add variable to .env file
  txt <- paste(name, value, sep = "=")
  write(txt, file=".env", append=TRUE)
  
}


cleardotenv <- function() {
  system("> .env")
}


get_env_var_list <- function() {
  unique(
    unlist(
      lapply(readLines(".env"), function(x) strsplit(x, "=")[[1]][1]
      )
    )
  )
}


run <- function(cmd, ..., test = FALSE) {
  args <- list(...)
  print(do.call(sprintf, c(cmd, args)))
  if (!test) {
    system(
      do.call(sprintf, c(cmd, args))
    )
  }
}


write_function <- function(fn, file) {
  fn_name <- deparse(substitute(fn))
  fn_capture <- capture.output(print(fn))
  fn_capture[1] <- paste0(fn_name, " <- ", fn_capture[1])
  writeLines(fn_capture, file)
}


download_blob_file <- function(f, cont) {
  tmpfile <- tempfile()
  download_blob(cont, src = f, dest = tmpfile)
  tmpfile
}


upload_blob_file <- function(x, f, cont, ...) {
  tmpfile <- tempfile()
  write.csv(x, tmpfile, ...)
  upload_blob(cont, src = tmpfile, dest = f)
}


load_model <- function(name, path, cont = NULL) {
  
  f <- file.path(path, name)
  if (!is.null(cont)) {
    tmpfile <- download_blob_file(f, cont)
    f <- tmpfile
  }
  list(name = name, model = readRDS(f))
  
}


load_models <- function(path = "models", cont = NULL) {
  
  model_names <-list_model_names(
    list_required_models(lagged_feature_steps = 6, quantiles = QUANTILES)
  )
  
  models <- lapply(model_names, load_model, path, cont)
  names(models) <- model_names
  models
  
}


terminate_all_jobs <- function() {
  jobs <- getJobList()
  job_ids <- jobs$Id
  lapply(job_ids, terminateJob)
}


delete_all_jobs <- function() {
  jobs <- getJobList()
  job_ids <- jobs$Id
  lapply(job_ids, deleteJob)
}

