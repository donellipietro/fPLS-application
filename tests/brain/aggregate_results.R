# = ========================================================================== =
# - Test: fPLS brain application - aggregate results
# - Desc: Writes separation and H-stability summaries when native fits exist.
# - Args:
#   [1] name_main_test
# = ========================================================================== =

rm(list = ls())
graphics.off()

suppressMessages(library(jsonlite))
suppressMessages(library(glue))

source("src/utils/directories.R")
source("src/utils/options.R")
source("tests/brain/config.R")
source("tests/brain/utils/generate_options.R")
source("tests/brain/utils/models_evaluation.R")

args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)

path_list <- create_paths(test_suite)
all_evaluations <- list()

for (family in families) {
  queue_dir <- file.path(path_list$queue, family)
  generate_options(test_suite, family, queue_dir)
  option_files <- sort(list.files(queue_dir, pattern = "[.]json$", full.names = TRUE))
  for (option_file in option_files) {
    options <- fromJSON(option_file, simplifyVector = TRUE)
    result_file <- file.path(
      path_list$results,
      family,
      options$name_test,
      "batch_1",
      "batch_1_results_evaluation.RData"
    )
    if (file.exists(result_file)) {
      load(result_file)
      all_evaluations[[options$name_test]] <- results_evaluation$R1_fPLS
    }
  }
}

if (length(all_evaluations) == 0L) {
  write_json(
    list(
      schema_version = 1L,
      requested = requested,
      run_complete = FALSE,
      status = "no_native_or_smoke_results_to_aggregate"
    ),
    file.path(aggregate_dir, "application_run_status.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("No results available to aggregate.\n")
  quit(save = "no", status = 0)
}

failed_names <- names(all_evaluations)[vapply(all_evaluations, function(x) isTRUE(x$failed), logical(1))]
if (length(failed_names) > 0L) {
  failures <- lapply(failed_names, function(name) {
    value <- all_evaluations[[name]]
    list(
      scenario = name,
      native_status = as.integer(value$status),
      validation_status = value$validation_status
    )
  })
  write_json(
    list(
      schema_version = 1L,
      requested = requested,
      run_complete = FALSE,
      status = "native_fit_failed",
      native_failures = failures
    ),
    file.path(aggregate_dir, "application_run_status.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("Native application fit failed; see the scenario log and application_run_status.json.\n")
  quit(save = "no", status = 2)
}

separation <- do.call(rbind, lapply(names(all_evaluations), function(name) {
  value <- all_evaluations[[name]]
  if (isTRUE(value$failed) || is.null(value$separation)) return(NULL)
  cbind(scenario = name, requested_components = value$n_comp, value$separation)
}))

if (!is.null(separation)) {
  write.csv(separation, file.path(aggregate_dir, "separation_by_H.csv"), row.names = FALSE)
}

write_json(
  list(
    schema_version = 1L,
    requested = requested,
    run_complete = TRUE,
    first_H_with_perfect_in_sample_separation = if (!is.null(separation) && any(separation$perfect_separation)) {
      as.character(min(separation$prefix_components[separation$perfect_separation]))
    } else "not_evaluated",
    prefix_diagnostics = "computed_from_single_H6_fit",
    distinct_fit_prefix_invariance = "not_estimated",
    bootstrap_component_significance = "not_implemented_decision_gated"
  ),
  file.path(aggregate_dir, "application_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("Application aggregation completed.\n")
