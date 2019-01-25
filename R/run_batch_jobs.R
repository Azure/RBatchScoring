run_batch_jobs <- function(chunks, vars_to_export) {
  
  foreach(
      idx=1:length(chunks),
      .options.azure = azure_options,
      .packages = pkgs_to_load,
      .export = vars_to_export
    ) %dopar% {
    
      file_dir <- "/mnt/batch/tasks/shared/files"
      
      models <- load_models(file.path(file_dir, "models"))
      
  
      products <- chunks[[idx]]
      
      for (product in products) {
        
        history <- read.csv(
          file.path(file_dir,
                    "data", "history",
                    paste0("product", product, ".csv"))
        ) %>%
          select(sku, store, week, sales)
        
        futurex <- read.csv(
          file.path(file_dir,
                    "data", "futurex",
                    paste0("product", product, ".csv"))
        )
        
        forecasts <- generate_forecast(
          futurex,
          history,
          models
        )
        
        write.csv(
          forecasts, 
          file.path(
            file_dir, "data", "forecasts",
            paste0("product", product, ".csv")),
          quote = FALSE, row.names = FALSE
        )
        
      }
      
      # Return arbitrary result                 
      TRUE
                           
    }
}
