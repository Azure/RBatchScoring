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


load_model <- function(name, path) {
  list(name = name, model = readRDS(file.path(path, name)))
}
