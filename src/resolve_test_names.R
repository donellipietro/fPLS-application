# = ========================================================================== =
# - Script: resolve_test_names.R
# - Desc: Prints runnable test names after expanding suite-level test groups.
# = ========================================================================== =

source("src/utils/test_groups.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript src/resolve_test_names.R <test_suite> <test_name> [test_name ...]", call. = FALSE)
}

test_suite <- args[1]
name_main_test <- args[-1]
cat(glue::glue_collapse(resolve_test_names(test_suite, name_main_test), sep = "\n"))
cat("\n")
