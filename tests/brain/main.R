# = ========================================================================== =
# - Test: fPLS brain application
# - Desc: Runs one complete-data or training-fold option through preparation, fit and evaluation.
# - Args:
#   [1] name_main_test: one configured application analysis
#   [2] file_options: one generated JSON option file
# = ========================================================================== =

## Start a clean application session ----
rm(list = ls())
graphics.off()

## Load libraries ----
suppressMessages(library(jsonlite))
suppressMessages(library(glue))

## Load application helpers and cache checks ----
source("src/utils/directories.R")
source("src/utils/options.R")
source("src/utils/process.R")
source("tests/brain/config.R")
source("tests/brain/utils/data_prep.R")
source("tests/brain/utils/projection.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/intrinsic_slider.R")
source("tests/brain/utils/slider_resampling.R")
source("tests/brain/utils/wrappers.R")
source("tests/brain/utils/fit_and_evaluate.R")
source("tests/brain/utils/models_evaluation.R")

## Prepare suite directories and read the queued option ----
path_list <- create_paths(test_suite)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: main.R <test-name> <option-file>")

# locate the queued JSON file within the requested application analysis
name_main_test <- args[1]
file_options <- args[2]
path_list$queue <- config_path(path_list$queue, name_main_test)
path_list$logs <- config_path(path_list$logs, name_main_test)
mkdir(c(path_list$queue, path_list$logs))

# resolve the full path of the queued JSON option selected by the runner
queue_file <- file.path(path_list$queue, file_options)

# read the data, model and resampling settings for this option
test_options <- fromJSON(queue_file, simplifyVector = TRUE)

# prepare output directories and resolve the compiled driver for this option
path_list <- update_paths(path_list, name_main_test, test_options)

## Record progress in the option log ----
sink(file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt")), append = FALSE)
cat(glue::glue("- Running: {test_suite} / {test_options$name_test}\n", .trim = FALSE))

## Prepare the complete sample or one resampling training fold ----
# each queued application option represents one fit, with its own data and results
path_list$batch <- config_path(path_list$results, "batch_1")
mkdir(path_list$batch)

is_resampling <- isTRUE(test_options$resampling$enabled)
# resampling saves split identifiers; complete-data analyses retain the prepared sample
data_file <- file.path(
  path_list$batch,
  if (is_resampling) "resampling_split_provenance.rds" else "prepared_data.rds"
)
# identify the private inputs and preparation code before considering a saved sample
input_md5 <- brain_input_md5(test_options$data$source_path)
preprocessing_md5 <- brain_preprocessing_md5()

# only complete-data samples are reused, and both input and preparation signatures must match
cached_data <- if (!is_resampling && file.exists(data_file) && !FORCE_FIT) readRDS(data_file) else NULL
if (!is.null(cached_data) &&
    isTRUE(all.equal(cached_data$input_md5, input_md5)) &&
    identical(cached_data$preprocessing_md5, preprocessing_md5)) {
  data <- cached_data
  cat("- Reuse prepared data\n")
} else {
  # load raw predictors, the tetrahedral mesh and the prevalence-weighted CTRL/SCHZ response
  full_data <- load_brain_application_data(test_options$data$source_path, input_md5)

  # select training subjects and recode their response; the native fit estimates their functional mean
  data <- if (is_resampling) {
    prepare_brain_resampling_split(
      full_data,
      test_options$resampling$n_folds,
      test_options$resampling$repeat_index,
      test_options$resampling$fold_index,
      test_options$resampling$seed,
      include_omitted_data = FALSE
    )
  } else full_data
  # save the full sample or the training-fold identifiers together with preparation metadata
  save_brain_prepared_data(data, data_file, test_options)
  cat(if (is_resampling) {
    "- Prepared slider-resampling training fold; omitted subjects are excluded from fitting\n"
  } else {
    "- Prepared raw complete data; native fit will estimate the overall functional mean\n"
  })
}

## Fit the selected model and evaluate the application quantities ----
# reuse a matching native fit or estimate it, then compute separation and slider diagnostics
test_options$batch_index <- 1L
fit_and_evaluate_models(
  path_list = path_list,
  data = data,
  domain = NULL,
  batch_index = 1L,
  test_options = test_options
)

## Finalize the completed option ----
# remove the queue entry only after preparation, fitting and evaluation have succeeded
unlink(queue_file)
# close the option log and restore console output
sink()
