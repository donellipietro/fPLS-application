# = ========================================================================== =
# - Test: fPLS brain application
# - Desc: Runs one application option through data prep and optional native fit.
# - Args:
#   [1] name_main_test
#   [2] file_options
# = ========================================================================== =

rm(list = ls())
graphics.off()

suppressMessages(library(jsonlite))
suppressMessages(library(glue))

source("src/utils/directories.R")
source("src/utils/load_results_utils.R")
source("src/utils/options.R")
source("tests/brain/config.R")
source("tests/brain/utils/data_prep.R")
source("tests/brain/utils/wrappers.R")
source("tests/brain/utils/fit_and_evaluate.R")
source("tests/brain/utils/models_evaluation.R")

path_list <- create_paths(test_suite)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: main.R <test-name> <option-file>")

name_main_test <- args[1]
file_options <- args[2]
path_list$queue <- config_path(path_list$queue, name_main_test)
path_list$logs <- config_path(path_list$logs, name_main_test)
mkdir(c(path_list$queue, path_list$logs))

queue_file <- file.path(path_list$queue, file_options)
test_options <- fromJSON(queue_file, simplifyVector = TRUE)
path_list <- update_paths(path_list, name_main_test, test_options)

sink(file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt")), append = TRUE)
cat(glue::glue("- Running: {test_suite} / {test_options$name_test}\n", .trim = FALSE))

path_list$batch <- config_path(path_list$results, "batch_1")
mkdir(path_list$batch)

data_file <- file.path(path_list$batch, "prepared_data.rds")
if (file.exists(data_file) && !FORCE_FIT) {
  data <- readRDS(data_file)
  cat("- Reuse prepared data\n")
} else {
  data <- load_brain_application_data(test_options$data$source_path)
  saveRDS(data, data_file)
  write_json(
    list(
      schema_version = 1L,
      source_path = test_options$data$source_path,
      centering = data$centering,
      response_counts = as.list(data$counts),
      n_subjects = data$dimensions$n_subjects,
      n_nodes = data$dimensions$n_nodes,
      n_tetrahedra = data$dimensions$n_tetrahedra,
      response_recoding = list(
        CTRL = "sqrt(p_SCHZ / p_CTRL)",
        SCHZ = "-sqrt(p_CTRL / p_SCHZ)"
      )
    ),
    file.path(path_list$batch, "data_preparation_provenance.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("- Prepared authoritative overall-mean centered data\n")
}

test_options$batch_index <- 1L
fit_and_evaluate_models(
  path_list = path_list,
  data = data,
  domain = NULL,
  batch_index = 1L,
  test_options = test_options
)

unlink(queue_file)
sink()
