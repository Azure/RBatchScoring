
library(jsonlite)
library(argparse)

parser <- ArgumentParser()
parser$add_argument("--clust", type="character",
                    help='cluster name')
parser$add_argument("--sa", type="character",
                    help="storage account name")
parser$add_argument("--sakey", type="character",
                    help="storage account key")
parser$add_argument("--share", type="character",
                    help="fileshare name")

args <- parser$parse_args()

mountStr <- "mount -t cifs //%s.file.core.windows.net/%s /mnt/batch/tasks/shared/data -o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,sec=ntlmssp"
mountCmd <- sprintf(mountStr, args$sa, args$share, args$sa, args$sakey)

commandLine = c("mkdir /mnt/batch/tasks/shared/data",
                mountCmd)

pkgs <- c("dplyr")

config = list(
  name = args$clust,
  vmSize = "Standard_D4s_v3",
  maxTasksPerNode = 1,
  poolSize = list(
      dedicatedNodes = list(
        min = 0,
        max = 0
      ),
      lowPriorityNodes = list(
        min = 10,
        max = 10
      ),
      autoscaleFormula = "QUEUE"
    ),
  rPackages = list(
    cran = pkgs
  ),
  
  commandLine = commandLine
)

configJson <- toJSON(config, auto_unbox = TRUE, pretty = TRUE)

write(configJson, file = file.path("azure", "cluster.json"))
