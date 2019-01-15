run_batch_jobs <- function(chunks, vars_to_export) {
  
  foreach(
      idx=1:length(chunks),
      .options.azure = azure_options,
      .packages = pkgs_to_load,
      .export = vars_to_export
    ) %dopar% {
    
      
      models <- load_models(file.path(file_dir, "models"))
  
      products <- chunks[[idx]]
      
      for (product in products) {
        
        forecasts <- generate_forecast(
          as.character(product),
          models,
          file_dir = file_dir
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
