create_cluster_json <- function(save_dir) {
  
  mountStr <- "mount -t cifs //%s.file.core.windows.net/%s /mnt/batch/tasks/shared/files -o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,sec=ntlmssp"
  mountCmd <- sprintf(mountStr,
                      Sys.getenv("STORAGE_ACCOUNT_NAME"),
                      Sys.getenv("FILE_SHARE_NAME"),
                      Sys.getenv("STORAGE_ACCOUNT_NAME"),
                      Sys.getenv("STORAGE_ACCOUNT_KEY")
                      )
  commandLine = c("mkdir /mnt/batch/tasks/shared/files", mountCmd)
  
  config = list(
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
    commandLine = commandLine
  )
  
  configJson <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(configJson, file = file.path(save_dir, "cluster.json"))
}