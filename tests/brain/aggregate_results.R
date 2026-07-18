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
suppressMessages(library(Matrix))

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

separation <- do.call(rbind, lapply(names(all_evaluations), function(name) {
  value <- all_evaluations[[name]]
  if (isTRUE(value$failed) || is.null(value$separation)) return(NULL)
  cbind(scenario = name, n_comp = value$n_comp, value$separation)
}))

stability <- NULL
h3_name <- names(all_evaluations)[vapply(all_evaluations, function(x) identical(x$n_comp, 3L), logical(1))]
larger <- names(all_evaluations)[vapply(all_evaluations, function(x) isTRUE(x$n_comp > 3L), logical(1))]
if (length(h3_name) > 0L && length(larger) > 0L) {
  reference <- all_evaluations[[h3_name[1]]]
  if (!is.null(reference$mass_triplets)) {
    M <- mass_matrix_from_triplets(reference$mass_triplets)
    stability <- do.call(rbind, lapply(larger, function(name) {
      estimate <- all_evaluations[[name]]
      do.call(rbind, lapply(seq_len(3L), function(h) {
        data.frame(
          reference = h3_name[1],
          scenario = name,
          n_comp = estimate$n_comp,
          component = h,
          mass_relative_distance = mass_relative_distance(
            reference$X_loadings[, h],
            estimate$X_loadings[, h],
            M
          )
        )
      }))
    }))
  }
}

if (!is.null(separation)) {
  write.csv(separation, file.path(aggregate_dir, "separation_by_H.csv"), row.names = FALSE)
}
if (!is.null(stability)) {
  write.csv(stability, file.path(aggregate_dir, "loading_stability_mass_norm.csv"), row.names = FALSE)
}

write_json(
  list(
    schema_version = 1L,
    requested = requested,
    run_complete = TRUE,
    first_H_with_perfect_in_sample_separation = if (!is.null(separation) && any(separation$perfect_separation)) {
      as.character(min(separation$n_comp[separation$perfect_separation]))
    } else "not_evaluated",
    stability_available = !is.null(stability),
    bootstrap_component_significance = "not_implemented_decision_gated"
  ),
  file.path(aggregate_dir, "application_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("Application aggregation completed.\n")
