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
suppressMessages(library(ggplot2))

source("src/utils/directories.R")
source("src/utils/options.R")
source("tests/brain/config.R")
source("tests/brain/utils/generate_options.R")
source("tests/brain/utils/models_evaluation.R")
source("tests/brain/utils/loading_stability.R")

args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)

path_list <- create_paths(test_suite)
all_evaluations <- list()
expected_names <- character()

for (family in families) {
  queue_dir <- file.path(path_list$queue, family)
  generate_options(test_suite, family, queue_dir)
  option_files <- sort(list.files(queue_dir, pattern = "[.]json$", full.names = TRUE))
  for (option_file in option_files) {
    options <- fromJSON(option_file, simplifyVector = TRUE)
    expected_names <- c(expected_names, options$name_test)
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

missing_names <- setdiff(expected_names, names(all_evaluations))

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

  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  separation_plot_data <- separation[separation$requested_components == max(separation$requested_components), , drop = FALSE]
  separation_long <- rbind(
    data.frame(prefix_components = separation_plot_data$prefix_components, metric = "AUC", value = separation_plot_data$auc),
    data.frame(prefix_components = separation_plot_data$prefix_components, metric = "Sensitivity", value = separation_plot_data$sensitivity),
    data.frame(prefix_components = separation_plot_data$prefix_components, metric = "Specificity", value = separation_plot_data$specificity)
  )
  separation_plot <- ggplot(separation_long, aes(prefix_components, value, colour = metric)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    scale_x_continuous(breaks = sort(unique(separation$prefix_components))) +
    scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
    labs(x = "Component prefix H", y = "In-sample separation", colour = NULL) +
    theme_bw() +
    theme(legend.position = "top")
  ggsave(
    file.path(image_dir, "separation_by_H.png"),
    separation_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )
}

stability <- NULL
if (requested == "h_stability" && all(c("h_stability_H3", "h_stability_H6") %in% names(all_evaluations))) {
  raw_root <- file.path(path_list$results, "h_stability")
  raw_dir <- function(name) file.path(raw_root, name, "batch_1", "raw", "R1_fPLS")
  reference_dir <- raw_dir("h_stability_H3")
  comparison_dir <- raw_dir("h_stability_H6")
  stability <- loading_stability(
    reference = as.matrix(read.csv(file.path(reference_dir, "x_loadings_coefficients.csv"), check.names = FALSE)),
    comparison = as.matrix(read.csv(file.path(comparison_dir, "x_loadings_coefficients.csv"), check.names = FALSE))[, seq_len(3L), drop = FALSE],
    points = as.matrix(read.csv(file.path(reference_dir, "points.csv"), check.names = FALSE)),
    elements = as.matrix(read.csv(file.path(reference_dir, "elements.csv"), check.names = FALSE))
  )
  write.csv(stability$per_component, file.path(aggregate_dir, "loading_stability_H3_vs_H6.csv"), row.names = FALSE)
  write.csv(stability$rotation, file.path(aggregate_dir, "loading_stability_rotation_H6_to_H3.csv"), row.names = FALSE)
  stability_plot <- ggplot(stability$per_component, aes(component, relative_mass_error)) +
    geom_col(fill = "#2b6cb0", width = 0.6) +
    scale_x_continuous(breaks = seq_len(3L)) +
    labs(x = "Loading function", y = "Relative FEM mass-norm difference") +
    theme_bw()
  ggsave(
    file.path(image_dir, "loading_stability_H3_vs_H6.png"),
    stability_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )
}

write_json(
  list(
    schema_version = 1L,
    requested = requested,
    run_complete = length(missing_names) == 0L,
    status = if (length(missing_names) == 0L) "complete" else "pending_required_fits",
    missing_scenarios = missing_names,
    first_H_with_perfect_in_sample_separation = if (!is.null(separation) && any(separation$perfect_separation)) {
      as.character(min(separation$prefix_components[separation$perfect_separation]))
    } else "not_evaluated",
    prefix_diagnostics = "computed_from_single_H6_fit",
    loading_stability = if (is.null(stability)) {
      "requires_independent_H3_and_H6_fits"
    } else {
      list(
        reference = "H3",
        comparison = "first_three_H6_loadings",
        alignment = "orthogonal_Procrustes_under_tetrahedral_P1_FEM_mass_inner_product",
        global_relative_mass_error = stability$global_relative_mass_error
      )
    },
    distinct_fit_prefix_invariance = "evaluated_as_H3_vs_first_three_H6_loading_stability",
    bootstrap_component_significance = "not_implemented_decision_gated"
  ),
  file.path(aggregate_dir, "application_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("Application aggregation completed.\n")
