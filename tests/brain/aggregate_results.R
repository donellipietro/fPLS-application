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
if (capabilities("cairo")) options(bitmapType = "cairo")

source("src/utils/directories.R")
source("src/utils/options.R")
source("tests/brain/config.R")
source("tests/brain/utils/generate_options.R")
source("tests/brain/utils/data_prep.R")
source("tests/brain/utils/cross_validation.R")
source("tests/brain/utils/models_evaluation.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/cv_aggregation.R")
source("tests/brain/utils/maximum_margin_stability.R")
source("tests/brain/utils/paraview_export.R")

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

if (requested == "out_of_sample") {
  expected_fits <- sum(vapply(families, function(family) {
    length(list.files(file.path(path_list$queue, family), pattern = "[.]json$"))
  }, integer(1)))
  if (length(all_evaluations) != expected_fits) {
    write_json(
      list(
        schema_version = 1L,
        requested = requested,
        run_complete = FALSE,
        status = "missing_cross_validation_fits",
        completed_fits = length(all_evaluations),
        expected_fits = expected_fits
      ),
      file.path(aggregate_dir, "application_run_status.json"),
      auto_unbox = TRUE,
      pretty = TRUE
    )
    stop(glue::glue("CV aggregation found {length(all_evaluations)} of {expected_fits} expected fits"))
  }
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  cv <- aggregate_cv_results(all_evaluations, aggregate_dir, image_dir, cfg)
  write_json(
    list(
      schema_version = 1L,
      requested = requested,
      run_complete = TRUE,
      status = "complete",
      design = list(
        method = "repeated_stratified_outer_cross_validation",
        repeats = cv$repeats,
        folds = cv$folds,
        native_fits = cv$fits,
        outer_split_unit = "subject",
        leakage_control = "centering_response_recoding_GCV_threshold_score_scaling_and_SVM_tuning_training_only",
        native_fit = glue::glue("one_progressive_H{cv$native_components}_fit_per_outer_fold"),
        primary_H = min(3L, cv$native_components),
        sensitivity_H = setdiff(cv$evaluated_components, min(3L, cv$native_components)),
        imbalance_handling = "stratified_folds_inverse_frequency_SVM_weights_and_class_sensitive_metrics"
      ),
      prediction = list(
        projection = "sequential_residual_projection_matching_native_fPLS_deflation",
        classifiers = c("PLS reconstructed response with training threshold", "class-weighted linear SVM"),
        positive_score_orientation = "CTRL",
        primary_metrics = c("SCHZ sensitivity", "SCHZ average precision", "SCHZ ROC AUC", "CTRL specificity", "balanced accuracy", "MCC")
      ),
      loading_reproducibility = list(
        quantities = c("Paper response loading", "SVM slider loading"),
        comparison = "pairwise_between_outer_training_fits_within_each_repeat",
        metric = "tetrahedral_P1_FEM_mass_correlation",
        orientation = "fixed_CTRL_positive_without_post_hoc_sign_alignment"
      ),
      uncertainty = "q025_and_q975_are_empirical_repeat_variability_not_formal_confidence_intervals",
      maximum_projection_abs_error = cv$max_projection_error
    ),
    file.path(aggregate_dir, "application_run_status.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("Out-of-sample CV aggregation completed.\n")
  quit(save = "no", status = 0)
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
maximum_margin_summary <- NULL
classifier_formula_max_abs_error <- NULL
if (requested == "h_stability" && "h_stability_H6" %in% names(all_evaluations)) {
  raw_dir <- file.path(path_list$results, "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
  batch_dir <- dirname(dirname(raw_dir))
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  points <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "points.csv"), check.names = FALSE)))
  elements <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "elements.csv"), check.names = FALSE)))
  x_loadings <- as.matrix(suppressWarnings(read.csv(
    file.path(raw_dir, "x_loadings_coefficients.csv"),
    check.names = FALSE
  )))
  y_loadings <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "y_loadings.csv"), check.names = FALSE)))
  loading_stability <- first_rotated_loading_stability(
    x_loadings = x_loadings,
    y_loadings = y_loadings,
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

  prepared_data <- readRDS(file.path(batch_dir, "prepared_data.rds"))
  x_directions <- as.matrix(suppressWarnings(read.csv(
    file.path(raw_dir, "x_space_directions_coefficients.csv"),
    check.names = FALSE
  )))
  maximum_margin_summary <- maximum_margin_prefix_sensitivity(
    scores = as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "x_latent_scores.csv"), check.names = FALSE))),
    x_loadings = x_loadings,
    x_directions = x_directions,
    labels = prepared_data$labels,
    points = points,
    elements = elements
  )

  classifier_formula_max_abs_error <- max(vapply(3:6, function(h) {
    directions_h <- x_directions[, seq_len(h), drop = FALSE]
    loadings_h <- x_loadings[, seq_len(h), drop = FALSE]
    reconstructed_beta <- directions_h %*% solve(
      crossprod(loadings_h, directions_h),
      as.numeric(y_loadings[1, seq_len(h)])
    )
    max(abs(reconstructed_beta - beta_coefficients[[as.character(h)]]))
  }, numeric(1)))
  if (classifier_formula_max_abs_error > 1e-10) {
    stop("score-space to functional coefficient reconstruction does not match native Beta(h)")
  }

  write.csv(
    maximum_margin_summary$diagnostics,
    file.path(aggregate_dir, "maximum_margin_sensitivity_by_H.csv"),
    row.names = FALSE
  )
  write.csv(
    maximum_margin_summary$spatial_stability,
    file.path(aggregate_dir, "maximum_margin_spatial_stability_by_H.csv"),
    row.names = FALSE
  )
  write.csv(
    maximum_margin_summary$boundaries,
    file.path(aggregate_dir, "maximum_margin_boundaries_by_H.csv"),
    row.names = FALSE
  )
  map_dir <- file.path(aggregate_dir, "maximum_margin_maps")
  dir.create(map_dir, recursive = TRUE, showWarnings = FALSE)
  for (h in 3:6) {
    write.csv(
      data.frame(coefficient = drop(maximum_margin_summary$reconstruction_maps[[as.character(h)]])),
      file.path(map_dir, glue::glue("reconstruction_loading_h{h}.csv")),
      row.names = FALSE
    )
    write.csv(
      data.frame(coefficient = drop(maximum_margin_summary$classifier_maps[[as.character(h)]])),
      file.path(map_dir, glue::glue("classifier_coefficient_h{h}.csv")),
      row.names = FALSE
    )
  }

  volumes <- tetrahedral_volumes(points, matrix(as.integer(elements), ncol = 4L))
  mass_unit <- function(values) {
    values <- matrix(as.numeric(values), ncol = 1L)
    drop(values / sqrt(drop(mass_crossprod(values, values, elements, volumes))))
  }
  paraview_fields <- list()
  for (h in 3:6) {
    beta_h <- drop(beta_coefficients[[as.character(h)]])
    gamma_h <- drop(maximum_margin_summary$classifier_maps[[as.character(h)]])
    f_h <- drop(maximum_margin_summary$reconstruction_maps[[as.character(h)]])
    paraview_fields[[glue::glue("beta_H{h}")]] <- beta_h
    paraview_fields[[glue::glue("gamma_H{h}")]] <- gamma_h
    paraview_fields[[glue::glue("f_H{h}")]] <- f_h
    paraview_fields[[glue::glue("beta_CTRL_unit_H{h}")]] <- mass_unit(beta_h)
    paraview_fields[[glue::glue("gamma_CTRL_unit_H{h}")]] <- mass_unit(gamma_h)
    paraview_fields[[glue::glue("f_CTRL_unit_H{h}")]] <- mass_unit(f_h)
  }
  paraview_dir <- file.path(aggregate_dir, "paraview")
  dir.create(paraview_dir, recursive = TRUE, showWarnings = FALSE)
  write_tetrahedral_vtu(
    file.path(paraview_dir, "maximum_margin_comparison.vtu"),
    points,
    elements,
    paraview_fields
  )
  file.copy(
    "tests/brain/paraview/maximum_margin_comparison.py",
    file.path(paraview_dir, "maximum_margin_comparison.py"),
    overwrite = TRUE
  )
  writeLines(c(
    "Maximum-margin ParaView comparison",
    "",
    "Run maximum_margin_comparison.py from ParaView's Python Shell, or launch:",
    glue::glue("paraview --script={file.path(paraview_dir, 'maximum_margin_comparison.py')}"),
    "",
    "The script opens a 3 x 4 linked-camera scene and writes a PVSM state plus a PNG preview.",
    "Rows: primary SVM slider loading f = R D q, then classifier controls gamma and beta.",
    "Columns: H = 3, 4, 5, 6. Scene fields are FEM-mass normalized and oriented positive toward CTRL.",
    "The VTU also contains the raw beta_H*, gamma_H*, and f_H* coefficient arrays."
  ), file.path(paraview_dir, "README.txt"))

  margin_plot <- ggplot(
    maximum_margin_summary$diagnostics,
    aes(retained_components, geometric_margin_standardized_scores)
  ) +
    geom_line(linewidth = 0.7, colour = "#007C91") +
    geom_point(size = 2, colour = "#007C91") +
    geom_text(aes(label = paste0("SV: ", support_vectors)), vjust = -0.8, size = 3.2) +
    scale_x_continuous(breaks = 3:6) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.15))) +
    labs(x = "Retained components H", y = "Maximum geometric margin (standardized scores)") +
    theme_bw()
  ggsave(
    file.path(image_dir, "maximum_margin_by_H.png"),
    margin_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )

  correlation_plot_data <- rbind(
    data.frame(
      retained_components = maximum_margin_summary$diagnostics$retained_components,
      quantity = "Score-space decision",
      correlation = maximum_margin_summary$diagnostics$decision_correlation_with_H3
    ),
    data.frame(
      retained_components = maximum_margin_summary$spatial_stability$retained_components,
      quantity = maximum_margin_summary$spatial_stability$quantity,
      correlation = maximum_margin_summary$spatial_stability$mass_correlation
    )
  )
  correlation_plot <- ggplot(
    correlation_plot_data,
    aes(retained_components, correlation, colour = quantity)
  ) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    scale_x_continuous(breaks = 3:6) +
    scale_y_continuous(breaks = seq(0, 1, 0.2)) +
    coord_cartesian(ylim = c(0, 1)) +
    labs(x = "Retained components H", y = "Correlation with H=3", colour = NULL) +
    theme_bw() +
    theme(legend.position = "top")
  ggsave(
    file.path(image_dir, "maximum_margin_correlations_by_H.png"),
    correlation_plot,
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
    separation_orientation = list(
      score_positive_class = "CTRL",
      auc_positive_class = "CTRL",
      sensitivity_class = "SCHZ",
      specificity_class = "CTRL"
    ),
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
    maximum_margin_sensitivity = if (is.null(maximum_margin_summary)) {
      "requires_H6_fit"
    } else {
      list(
        classifier = "linear_C_SVM_cost_1e6_verified_hard_margin",
        score_scaling = "componentwise_training_mean_and_standard_deviation_prefix_consistent",
        class_orientation = "positive_is_CTRL_matching_paper_response_coding",
        auc_positive_class = "CTRL",
        sensitivity_class = "SCHZ",
        specificity_class = "CTRL",
        reconstruction_loading = "R_H_times_score_SD_times_unit_standardized_SVM_normal",
        classifier_coefficient = "W_H_times_inverse_RtW_times_score_space_boundary_normal",
        spatial_metric = "tetrahedral_P1_FEM_mass_correlation_with_H3",
        paraview_bundle = "aggregate/h_stability/paraview/maximum_margin_comparison.vtu_and_scene_script",
        classifier_formula_max_abs_error_against_native_beta = classifier_formula_max_abs_error
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
