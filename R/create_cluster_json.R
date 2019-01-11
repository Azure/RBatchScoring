create_cluster_json <- function(save_dir = "azure") {
  
  mount_str <- paste(
    "mount -t cifs //%s.file.core.windows.net/%s /mnt/batch/tasks/shared/files",
    "-o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,sec=ntlmssp"
  )
  mount_cmd <- sprintf(
    mount_str,
    Sys.getenv("STORAGE_ACCOUNT_NAME"),
    Sys.getenv("FILE_SHARE_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_NAME"),
    Sys.getenv("STORAGE_ACCOUNT_KEY")
  )
  cmd_line <- c("mkdir /mnt/batch/tasks/shared/files", mount_cmd)
  
  config <- list(
    name = Sys.getenv("CLUSTER_NAME"),
    vmSize = Sys.getenv("VM_SIZE"),
    maxTasksPerNode = 1,
    poolSize = list(
      dedicatedNodes = list(
        min = as.integer(Sys.getenv("NUM_NODES")),
        max = as.integer(Sys.getenv("NUM_NODES"))
      ),
      lowPriorityNodes = list(
        min = 0,
        max = 0
      ),
      autoscaleFormula = "QUEUE_AND_RUNNING"
    ),
    containerImage = Sys.getenv("WORKER_CONTAINER_IMAGE"),
    commandLine = cmd_line
  )
  
  config_json <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(config_json, file = file.path(save_dir, "cluster.json"))
  
}
