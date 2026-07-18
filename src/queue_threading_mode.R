# = ========================================================================== =
# - Script: queue_threading_mode.R
# - Desc: Prints the threading mode declared by a generated queue.
# = ========================================================================== =

suppressMessages(library(jsonlite))

source("src/utils/directories.R")
source("src/utils/test_groups.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: Rscript src/queue_threading_mode.R <test_suite> <test_name>", call. = FALSE)
}

test_suite <- args[1]
test_name <- args[2]

cfg <- load_config()
path_queue <- config_path(cfg$PATH_QUEUE, test_suite, test_name)
cat(queue_threading_mode(path_queue))
cat("\n")
