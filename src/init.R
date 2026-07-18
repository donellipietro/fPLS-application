# = ========================================================================== =
# - Script: init.R
# - Desc: Initializes a test run by parsing CLI arguments, preparing
#         directories, and generating JSON option files for the selected test.
# = ========================================================================== =

# Libraries ----
suppressMessages(library(jsonlite))
suppressMessages(library(RColorBrewer))

# Sources ----
source("src/utils/options.R")
source("src/utils/directories.R")
source("src/utils/test_groups.R")

# Select test ----

## Read arguments passed from the terminal
args <- commandArgs(trailingOnly = TRUE)

## Parse the arguments, if any
if (length(args) == 0) {
  ## Defaults
  test_suite     <- "smoothing-example"
  name_main_test <- "all"
} else {
  ## Set the requested configuration
  test_suite     <- args[1]
  name_main_test <- args[2]
}

## Print selected test info
cat("\n")
cat(glue::glue("Test suite: {test_suite}\n", .trim = FALSE))
cat(glue::glue("Test name: {name_main_test}\n", .trim = FALSE))
cat("\n")

path_test_suite <- file.path("tests", test_suite)
path_generate_options <- file.path(path_test_suite, "utils", "generate_options.R")
path_suite_config <- file.path(path_test_suite, "config.R")
if (!dir.exists(path_test_suite) || !file.exists(path_generate_options)) {
  available_suites <- basename(list.dirs("tests", recursive = FALSE, full.names = TRUE))
  stop(
    glue::glue(
      "Unknown or incomplete test suite: {test_suite}\n",
      "Expected option generator: {path_generate_options}\n",
      "Available test suites: {glue::glue_collapse(sort(available_suites), sep = ', ')}"
    ),
    call. = FALSE
  )
}

# Generate options ----

## Update directories according to the selected test
cfg <- load_config()
mkdir(c(cfg$PATH_TMP, cfg$PATH_QUEUE))
path_queue <- config_path(cfg$PATH_QUEUE, test_suite)
mkdir(path_queue)

## Load the option-generation function
if (file.exists(path_suite_config)) {
  source(path_suite_config)
}
source(path_generate_options)

## Generate all the options for the selected test(s)
resolved_tests <- resolve_test_names(test_suite, name_main_test)
if (length(resolved_tests) > 1 || !identical(resolved_tests, name_main_test)) {
  cat(glue::glue(
    "Resolved tests: {glue::glue_collapse(resolved_tests, sep = ', ')}\n\n",
    .trim = FALSE
  ))
}

for (test_name in resolved_tests) {
  path_queue_i <- config_path(path_queue, test_name)
  mkdir(path_queue_i)
  generate_options(test_suite, test_name, path_queue_i)
}
