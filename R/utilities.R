
read_all_data <- function(filedir) {
  files2read = list.files(path = file.path(filedir, "data"), pattern="*.csv", full.names = TRUE)
  files = lapply(files2read, read.csv)
  do.call(rbind, files)
}

df2list <- function(store_brand, dat, start = c(1, 1)) {
  s <- store_brand$store
  b <- store_brand$brand
  df <- dat %>% filter(store == s, brand == b)
  xreg <- df %>%
    select(
      price1,
      price2,
      price3,
      price4,
      price5,
      price6,
      price7,
      price8,
      price9,
      price10,
      price11,
      deal,
      feat
    )
  list(store = s, brand = b,
       series =  df %>%
         select(logsales) %>%
         ts(frequency = 52, start = start),
       xreg = xreg
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