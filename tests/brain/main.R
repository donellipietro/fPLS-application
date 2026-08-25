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
source("tests/brain/utils/cross_validation.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/maximum_margin_stability.R")
source("tests/brain/utils/slider_resampling.R")
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

sink(file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt")), append = FALSE)
cat(glue::glue("- Running: {test_suite} / {test_options$name_test}\n", .trim = FALSE))

path_list$batch <- config_path(path_list$results, "batch_1")
mkdir(path_list$batch)

is_cv <- isTRUE(test_options$cross_validation$enabled)
data_file <- file.path(path_list$batch, if (is_cv) "cv_split_provenance.rds" else "prepared_data.rds")
input_md5 <- brain_input_md5(test_options$data$source_path)
preprocessing_md5 <- brain_preprocessing_md5()
cached_data <- if (!is_cv && file.exists(data_file) && !FORCE_FIT) readRDS(data_file) else NULL
if (!is.null(cached_data) &&
    isTRUE(all.equal(cached_data$input_md5, input_md5)) &&
    identical(cached_data$preprocessing_md5, preprocessing_md5)) {
  data <- cached_data
  cat("- Reuse prepared data\n")
} else {
  full_data <- load_brain_application_data(test_options$data$source_path, input_md5)
  data <- if (is_cv) {
    prepare_brain_cv_split(
      full_data,
      test_options$cross_validation$n_folds,
      test_options$cross_validation$repeat_index,
      test_options$cross_validation$fold_index,
      test_options$cross_validation$seed,
      include_omitted_data = !identical(
        test_options$cross_validation$purpose, "interpretive_slider_stability"
      )
    )
  } else full_data
  saveRDS(
    if (is_cv) {
      list(
        cross_validation = data$cross_validation[c(
          "n_folds", "repeat_index", "fold_index", "seed", "train_indices", "test_indices", "test_counts"
        )],
        train_counts = data$counts,
        mean_estimation_scope = data$centering,
        input_md5 = data$input_md5,
        preprocessing_md5 = data$preprocessing_md5
      )
    } else data,
    data_file
  )
  write_json(
    list(
      schema_version = 1L,
      source_path = test_options$data$source_path,
      input_md5 = as.list(data$input_md5),
      preprocessing_md5 = data$preprocessing_md5,
      centering = data$centering,
      mean_estimation = test_options$mean_estimation,
      response_counts = as.list(data$counts),
      n_subjects = data$dimensions$n_subjects,
      n_nodes = data$dimensions$n_nodes,
      n_tetrahedra = data$dimensions$n_tetrahedra,
      cross_validation = if (is_cv) list(
        repeat_index = data$cross_validation$repeat_index,
        fold_index = data$cross_validation$fold_index,
        n_folds = data$cross_validation$n_folds,
        train_indices = data$cross_validation$train_indices,
        test_indices = data$cross_validation$test_indices,
        test_counts = as.list(data$cross_validation$test_counts),
        leakage_control = if (identical(
          test_options$cross_validation$purpose, "interpretive_slider_stability"
        )) "omitted_subjects_not_used_functional_mean_response_GCV_and_slider_fit_on_training_only" else
          "functional_mean_response_GCV_threshold_and_classifier_fit_on_training_only"
      ) else NULL,
      response_recoding = list(
        CTRL = "sqrt(p_SCHZ / p_CTRL)",
        SCHZ = "-sqrt(p_CTRL / p_SCHZ)"
      )
    ),
    file.path(path_list$batch, "data_preparation_provenance.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat(if (is_cv) {
    if (identical(test_options$cross_validation$purpose, "interpretive_slider_stability")) {
      "- Prepared slider-resampling training fold; omitted subjects will not be used\n"
    } else {
      "- Prepared raw training-only CV fold; native fit will estimate its functional mean\n"
    }
  } else {
    "- Prepared raw complete data; native fit will estimate the overall functional mean\n"
  })
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
