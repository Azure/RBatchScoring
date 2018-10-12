
create_cluster_config <- function() {
  
  #mountStr <- "mount -t cifs //%s.file.core.windows.net/%s /mnt/batch/tasks/shared/data -o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,sec=ntlmssp"
  #mountCmd <- sprintf(mountStr, RBATCH_SA, RBATCH_SHARE, RBATCH_SA, RBATCH_SA_KEY)
  #commandLine = c("mkdir /mnt/batch/tasks/shared/data",
  #                mountCmd)
  commandLine = c()
  
  config = list(
    name = RBATCH_CLUST,
    vmSize = "Standard_D4s_v3",
    maxTasksPerNode = 4,
    poolSize = list(
        dedicatedNodes = list(
          min = 5,
          max = 5
        ),
        lowPriorityNodes = list(
          min = 0,
          max = 0
        ),
        autoscaleFormula = "QUEUE"
      ),
    containerImage = "angusrtaylor/batchforecasting",
    commandLine = commandLine
  )
  
  configJson <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  
  write(configJson, file = file.path("azure", "cluster.json"))
}

