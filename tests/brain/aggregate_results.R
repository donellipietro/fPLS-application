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

loading_stability <- NULL
beta_stability_summary <- NULL
if (requested == "h_stability" && "h_stability_H6" %in% names(all_evaluations)) {
  raw_dir <- file.path(path_list$results, "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
  points <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "points.csv"), check.names = FALSE)))
  elements <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "elements.csv"), check.names = FALSE)))
  loading_stability <- first_rotated_loading_stability(
    x_loadings = as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "x_loadings_coefficients.csv"), check.names = FALSE))),
    y_loadings = as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "y_loadings.csv"), check.names = FALSE))),
    points = points,
    elements = elements
  )
  beta_coefficients <- setNames(lapply(3:6, function(h) {
    as.matrix(suppressWarnings(read.csv(file.path(raw_dir, glue::glue("beta_coefficients_h{h}.csv")), check.names = FALSE)))
  }), as.character(3:6))
  beta_stability_summary <- beta_stability(beta_coefficients, points, elements)
  stability <- rbind(
    transform(loading_stability$summary, quantity = "Decision-boundary loading f1"),
    transform(beta_stability_summary$summary, quantity = "Regression coefficient beta")
  )
  write.csv(stability, file.path(aggregate_dir, "decision_boundary_and_beta_stability_by_H.csv"), row.names = FALSE)
  stability_plot <- ggplot(stability, aes(retained_components, relative_mass_error, colour = quantity)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    scale_x_continuous(breaks = 3:6) +
    labs(x = "Retained components H", y = "Relative FEM mass-norm difference from H=3", colour = NULL) +
    theme_bw() +
    theme(legend.position = "top")
  ggsave(
    file.path(image_dir, "decision_boundary_and_beta_stability_by_H.png"),
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
    run_complete = TRUE,
    status = "complete",
    first_H_with_perfect_in_sample_separation = if (!is.null(separation) && any(separation$perfect_separation)) {
      as.character(min(separation$prefix_components[separation$perfect_separation]))
    } else "not_evaluated",
    prefix_diagnostics = "computed_from_single_H6_fit",
    decision_boundary_loading_stability = if (is.null(loading_stability)) {
      "requires_H6_fit"
    } else {
      list(
        reference = "rotated_H3_prefix",
        comparisons = "rotated_H4_to_H6_prefixes_first_loading_only",
        rotation = "historical_Gram_Schmidt_Y_loading_basis",
        metric = "sign_aligned_tetrahedral_P1_FEM_mass_relative_norm",
        rotated_loadings_2_and_3 = "not_reported_not_scientific_targets"
      )
    },
    beta_stability = if (is.null(beta_stability_summary)) {
      "requires_H6_fit"
    } else {
      list(
        reference = "native_Beta_H3",
        comparisons = "native_Beta_H4_to_H6",
        definition = "model.Beta(h)_exported_as_beta_coefficients_h.csv",
        metric = "tetrahedral_P1_FEM_mass_relative_norm_without_sign_flip_response_orientation_fixed"
      )
    },
    distinct_fit_prefix_invariance = "not_applicable_single_progressive_fit",
    bootstrap_component_significance = "not_implemented_decision_gated"
  ),
  file.path(aggregate_dir, "application_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("Application aggregation completed.\n")
