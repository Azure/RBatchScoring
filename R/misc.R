run("rm ../bffs/data/forecasts/*")

run("ls -l ../bffs/data/forecasts | wc -l")

run("ls ../bffs/data/forecasts")


job <-"job20190111092554"

getJobFile(job, "1", "wd/1.txt")
getJobFile(job, "1", "stderr.txt")
getJobFile(job, "1", "stdout.txt")