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
plot_file <- function(directory, stem) {
  file.path(directory, paste0(stem, if (capabilities("cairo")) ".png" else ".pdf"))
}

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
source("tests/brain/utils/slider_resampling.R")
source("tests/brain/utils/paraview_export.R")

args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)

path_list <- create_paths(test_suite)
all_evaluations <- list()
expected_evaluations <- character()

model_reducer_label <- function(model_name) {
  if (identical(model_name, "R1_fPLS")) "R1-fPLS" else if (identical(model_name, "fPCR")) "fPCR" else model_name
}

for (family in families) {
  queue_dir <- file.path(path_list$queue, family)
  generate_options(test_suite, family, queue_dir)
  option_files <- sort(list.files(queue_dir, pattern = "[.]json$", full.names = TRUE))
  for (option_file in option_files) {
    options <- fromJSON(option_file, simplifyVector = TRUE)
    model_names <- as.character(options$model_names)
    evaluation_keys <- paste(options$name_test, model_names, sep = "::")
    expected_evaluations <- c(expected_evaluations, evaluation_keys)
    result_file <- file.path(
      path_list$results,
      family,
      options$name_test,
      "batch_1",
      "batch_1_results_evaluation.RData"
    )
    if (file.exists(result_file)) {
      load(result_file)
      for (model_name in intersect(model_names, names(results_evaluation))) {
        value <- results_evaluation[[model_name]]
        value$scenario <- options$name_test
        if (is.null(value$dimension_reducer)) {
          value$dimension_reducer <- model_reducer_label(model_name)
        }
        all_evaluations[[paste(options$name_test, model_name, sep = "::")]] <- value
      }
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
      scenario = value$scenario,
      dimension_reducer = value$dimension_reducer,
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

regularization_boundaries <- do.call(rbind, lapply(names(all_evaluations), function(name) {
  value <- all_evaluations[[name]]
  if (is.null(value$regularization_boundaries)) return(NULL)
  cbind(
    scenario = value$scenario,
    dimension_reducer = value$dimension_reducer,
    value$regularization_boundaries
  )
}))

fpls_loading_gcv <- do.call(rbind, lapply(names(all_evaluations), function(name) {
  value <- all_evaluations[[name]]
  if (is.null(value$fpls_loading_gcv)) return(NULL)
  cbind(scenario = value$scenario, value$fpls_loading_gcv)
}))
all_gcv_selections_interior <- is.null(regularization_boundaries) || !any(
  regularization_boundaries$selected_at_lower_boundary |
    regularization_boundaries$selected_at_upper_boundary
)

if (requested %in% c("slider_resampling", "fpcr_slider_resampling")) {
  missing_evaluations <- setdiff(expected_evaluations, names(all_evaluations))
  if (length(missing_evaluations) > 0L) {
    write_json(
      list(
        schema_version = 2L,
        requested = requested,
        run_complete = FALSE,
        status = "missing_slider_resampling_fits",
        completed_fits = length(all_evaluations),
        expected_fits = length(expected_evaluations),
        missing_evaluations = missing_evaluations
      ),
      file.path(aggregate_dir, "application_run_status.json"),
      auto_unbox = TRUE,
      pretty = TRUE
    )
    stop(glue::glue(
      "Slider-resampling aggregation found {length(all_evaluations)} of {length(expected_evaluations)} expected fits"
    ))
  }
  validation_statuses <- unique(vapply(all_evaluations, function(value) {
    as.character(value$provenance$validation_status)
  }, character(1)))
  run_status <- if (identical(validation_statuses, "slider_resampling_smoke")) {
    "smoke_complete"
  } else if (identical(validation_statuses, "slider_resampling_production")) {
    "production_complete"
  } else if (identical(validation_statuses, "slider_resampling_noncanonical")) {
    "noncanonical_complete"
  } else {
    stop("slider-resampling evaluations have missing or mixed validation provenance")
  }
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  resampling <- aggregate_slider_resampling(all_evaluations, aggregate_dir, image_dir, cfg)
  test_structure <- aggregate_slider_test_explained_structure(
    all_evaluations, requested, aggregate_dir, image_dir, cfg
  )
  if (!resampling$all_H3_hard_margin_separable) {
    run_status <- paste0(run_status, "_with_nonseparable_H3_training_folds")
  }
  if (!resampling$all_GCV_selections_interior) {
    run_status <- paste0(run_status, "_with_GCV_boundary_selection")
  }
  write_json(
    list(
      schema_version = 2L,
      requested = requested,
      run_complete = TRUE,
      status = run_status,
      validation_status = validation_statuses,
      design = list(
        method = "repeated_stratified_delete_one_fold_training_sample_stability",
        repeats = resampling$repeats,
        folds = resampling$folds,
        native_fits = resampling$fits,
        dimension_reducer = resampling$dimension_reducer,
        native_fit = paste0("one_progressive_", resampling$dimension_reducer, "_H6_fit_per_training_fold"),
        stratification = "class_labels_used_only_to_construct_fold_assignment",
        omitted_subjects_usage = "excluded_from_fit_and_slider_stability_then_used_only_for_postfit_structural_evaluation",
        test_predictions_or_metrics = "held_out_X_Y_and_XY_explained_structure_without_test_tuning",
        complete_data_reference = paste0(
          "accepted_H3_slider_from_", resampling$complete_data_reference_target
        ),
        complete_data_reference_status = resampling$complete_data_reference_status,
        complete_data_reference_first_H = resampling$complete_data_reference_first_H,
        complete_data_reference_H3_hard_margin = resampling$complete_data_reference_H3_hard_margin,
        complete_data_reference_map_md5 = resampling$complete_data_reference_map_md5,
        complete_reference_overlap_caveat = "descriptive_stability_not_independent_validation"
      ),
      slider = list(
        definition = "R_H_times_score_SD_times_unit_standardized_SVM_normal",
        retained_components = 3L,
        fixed_SVM_cost = 1e6,
        class_orientation = "positive_is_CTRL",
        posthoc_sign_alignment = FALSE,
        comparable_training_fits = resampling$comparable_H3_fits,
        all_training_fits_H3_hard_margin_separable = resampling$all_H3_hard_margin_separable,
        metrics = c("tetrahedral_P1_FEM_mass_correlation_rho_H3", "relative_FEM_mass_error_e_H3")
      ),
      training_prefix_separation = list(
        prefixes = 1:6,
        output = "slider_resampling_Hmin_distribution.csv"
      ),
      held_out_explained_structure = list(
        unit = "one_curve_per_repeat_and_test_fold",
        prefixes = 1:6,
        metrics = c(
          "X_variance_explained", "Y_variance_explained",
          "XY_cross_covariance_explained"
        ),
        norm = "observation_location_Frobenius_matching_simulation_study",
        FEM_mass_matrix = "not_used",
        predictor_centering_and_projection = "training_fit_only",
        response_coding = "training_fold_prevalence_weights_applied_to_test_labels",
        response_prediction = "training_only_prefix_coefficients_verified_against_native_Yhat",
        full_data_source = paste0(
          resampling$complete_data_reference_target, "_H6/batch_1/prepared_data.rds"
        ),
        mesh_source = paste0(
          resampling$complete_data_reference_target, "_H6/batch_1/raw/",
          if (identical(resampling$dimension_reducer, "fPCR")) "fPCR" else "R1_fPLS",
          "/points.csv_and_elements.csv"
        ),
        test_tuning_or_selection = "none",
        negative_values = "retained_not_truncated",
        fold_curves = "slider_resampling_test_explained_structure_by_fold.csv",
        descriptive_summary = "slider_resampling_test_explained_structure_summary.csv",
        native_fit_application_commit = test_structure$native_application_commit,
        postprocessing_application_commit = trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE))[1]
      ),
      all_test_data_unused_for_fitting_and_slider_stability = resampling$all_test_data_unused,
      held_out_test_data_used_for_postfit_explained_structure = TRUE,
      all_production_GCV_selections_interior = resampling$all_GCV_selections_interior,
      uncertainty = "descriptive_overlapping_training_sets_not_independent_replicates"
    ),
    file.path(aggregate_dir, "application_run_status.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("Slider-resampling aggregation completed.\n")
  quit(save = "no", status = 0)
}

if (requested == "out_of_sample") {
  missing_evaluations <- setdiff(expected_evaluations, names(all_evaluations))
  if (length(missing_evaluations) > 0L) {
    write_json(
      list(
        schema_version = 2L,
        requested = requested,
        run_complete = FALSE,
        status = "missing_cross_validation_fits",
        completed_fits = length(all_evaluations),
        expected_fits = length(expected_evaluations),
        missing_evaluations = missing_evaluations
      ),
      file.path(aggregate_dir, "application_run_status.json"),
      auto_unbox = TRUE,
      pretty = TRUE
    )
    stop(glue::glue(
      "CV aggregation found {length(all_evaluations)} of {length(expected_evaluations)} expected reducer fits"
    ))
  }
  validation_statuses <- unique(vapply(all_evaluations, function(value) {
    status <- value$provenance$validation_status
    if (is.null(status)) NA_character_ else as.character(status)
  }, character(1)))
  run_status <- if (identical(validation_statuses, "cross_validation_smoke")) {
    "smoke_complete"
  } else if (identical(validation_statuses, "cross_validation_production")) {
    "production_complete"
  } else if (identical(validation_statuses, "cross_validation_noncanonical")) {
    "noncanonical_complete"
  } else {
    write_json(
      list(
        schema_version = 2L,
        requested = requested,
        run_complete = FALSE,
        status = "mixed_or_missing_validation_provenance",
        validation_statuses = validation_statuses
      ),
      file.path(aggregate_dir, "application_run_status.json"),
      auto_unbox = TRUE,
      pretty = TRUE
    )
    stop("CV evaluations have missing or mixed saved validation provenance: ", paste(validation_statuses, collapse = ", "))
  }
  if (identical(run_status, "production_complete") && !all_gcv_selections_interior) {
    run_status <- "production_complete_with_GCV_boundary_selection"
  }
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  write_json(
    list(
      schema_version = 2L,
      requested = requested,
      run_complete = FALSE,
      status = "aggregation_in_progress"
    ),
    file.path(aggregate_dir, "application_run_status.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cv <- aggregate_cv_results(all_evaluations, aggregate_dir, image_dir, cfg)
  write_json(
    list(
      schema_version = 2L,
      requested = requested,
      run_complete = TRUE,
      status = run_status,
      design = list(
        method = "repeated_stratified_outer_cross_validation",
        repeats = cv$repeats,
        folds = cv$folds,
        native_fits = cv$fits,
        native_fits_by_dimension_reducer = cv$fits_by_reducer,
        dimension_reducers = cv$dimension_reducers,
        outer_split_unit = "subject",
        leakage_control = "outer_test_untouched_by_centering_response_recoding_GCV_fPCA_GCV_latent_response_OLS_threshold_score_scaling_and_SVM_tuning",
        native_fit = glue::glue("one_progressive_H{cv$native_components}_fit_per_dimension_reducer_and_outer_fold"),
        primary_H = min(3L, cv$native_components),
        sensitivity_H = setdiff(cv$evaluated_components, min(3L, cv$native_components)),
        imbalance_handling = "stratified_folds_inverse_frequency_SVM_weights_and_class_sensitive_metrics"
      ),
      prediction = list(
        axes = c("dimension_reducer", "classifier"),
        projection = "reducer_specific_sequential_residual_projection_verified_against_native_training_scores",
        classifiers = c("training_only_OLS_latent_response_with_training_threshold", "class-weighted linear SVM"),
        svm_tuning_scope = "classifier_only_inner_CV_conditional_on_the_outer_training_fitted_reducer_not_full_nested_pipeline_CV",
        positive_score_orientation = "CTRL",
        primary_metrics = c("SCHZ sensitivity", "SCHZ average precision", "SCHZ ROC AUC", "CTRL specificity", "balanced accuracy", "MCC")
      ),
      loading_reproducibility = list(
        quantities = c("Latent response loading", "SVM slider loading"),
        comparison = "pairwise_between_outer_training_fits_within_each_repeat_and_dimension_reducer",
        metric = "tetrahedral_P1_FEM_mass_correlation",
        orientation = "fixed_CTRL_positive_without_post_hoc_sign_alignment",
        cross_reducer_mixing = "never"
      ),
      slider_map_assessment = list(
        within_fit_cross_H = list(
          reference = "the_same_outer_training_fit_H3_SVM_slider_loading",
          comparisons = "H4_to_H6_when_available",
          metric = "tetrahedral_P1_FEM_mass_correlation_without_sign_alignment"
        ),
        complete_data_comparison = list(
          dimension_reducer = cv$complete_data_reference$dimension_reducer,
          reference = "matching_H_complete_data_R1_fPLS_SVM_slider_loading",
          available_components = as.integer(names(cv$complete_data_reference$maps)),
          missing_components = cv$complete_data_reference$missing_components,
          caveat = "descriptive_overlap_check_only_complete_fit_contains_each_outer_training_set"
        ),
        consensus_maps = list(
          directory = "cv_slider_consensus_maps",
          subdirectories = vapply(cv$dimension_reducers, reducer_slug, character(1)),
          definition = "within_dimension_reducer_mean_of_CTRL_oriented_unit_FEM_norm_outer_fit_slider_maps_then_unit_FEM_normalized",
          caveat = "resampling_summary_not_the_slider_loading_of_a_single_fitted_model"
        )
      ),
      regularization_outputs = list(
        fpls = "cv_selected_fpls_lambdas.csv",
        fpca = "cv_selected_fpca_lambdas.csv",
        boundary_diagnostics = "cv_regularization_boundary_diagnostics.csv",
        all_production_selections_interior = all_gcv_selections_interior,
        fpca_gcv = "application_local_power_iteration_with_explicit_Hutchinson_probe_count_and_seed"
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

if (requested %in% c("h_stability", "fpcr_h_stability")) {
  validation_statuses <- unique(vapply(all_evaluations, function(value) {
    status <- value$provenance$validation_status
    if (is.null(status)) NA_character_ else as.character(status)
  }, character(1)))
  if (!identical(validation_statuses, "complete_data_production")) {
    write_json(
      list(
        schema_version = 2L,
        requested = requested,
        run_complete = FALSE,
        status = "missing_complete_data_production_provenance",
        validation_statuses = validation_statuses
      ),
      file.path(aggregate_dir, "application_run_status.json"),
      auto_unbox = TRUE,
      pretty = TRUE
    )
    stop("Complete-data slider aggregation requires complete_data_production provenance")
  }
  complete_resources <- do.call(rbind, lapply(all_evaluations, function(value) {
    data.frame(
      scenario = value$scenario,
      dimension_reducer = value$dimension_reducer,
      wall_seconds = as.numeric(value$execution_time),
      peak_ram_mib = as.numeric(value$peak_ram_mib),
      max_component_iterations = max(as.integer(value$iteration_count)),
      any_component_hit_max_iter = any(as.logical(value$hit_max_iter)),
      all_components_monotone = all(as.logical(value$monotone)),
      all_components_finite = all(as.logical(value$finite_solution))
    )
  }))
  write.csv(
    complete_resources,
    file.path(aggregate_dir, "complete_data_resources.csv"),
    row.names = FALSE
  )
}

if (!is.null(regularization_boundaries)) {
  write.csv(
    regularization_boundaries,
    file.path(aggregate_dir, "regularization_boundary_diagnostics.csv"),
    row.names = FALSE
  )
}
if (!is.null(fpls_loading_gcv)) {
  write.csv(
    fpls_loading_gcv,
    file.path(aggregate_dir, "fpls_loading_gcv.csv"),
    row.names = FALSE
  )
}

separation <- do.call(rbind, lapply(names(all_evaluations), function(name) {
  value <- all_evaluations[[name]]
  if (isTRUE(value$failed) || is.null(value$separation)) return(NULL)
  cbind(
    scenario = value$scenario,
    dimension_reducer = value$dimension_reducer,
    requested_components = value$n_comp,
    value$separation
  )
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
    plot_file(image_dir, "separation_by_H"),
    separation_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )
}

beta_stability_summary <- NULL
maximum_margin_summary <- NULL
classifier_formula_max_abs_error <- NULL
complete_reducer <- if (identical(requested, "fpcr_h_stability")) "fPCR" else "R1-fPLS"
complete_model <- if (identical(complete_reducer, "fPCR")) "fPCR" else "R1_fPLS"
complete_scenario <- paste0(requested, "_H6")
has_complete_h6 <- any(vapply(all_evaluations, function(value) {
  identical(value$scenario, complete_scenario) && identical(value$dimension_reducer, complete_reducer)
}, logical(1)))
if (requested %in% c("h_stability", "fpcr_h_stability") && has_complete_h6) {
  raw_dir <- file.path(path_list$results, requested, complete_scenario, "batch_1", "raw", complete_model)
  batch_dir <- dirname(dirname(raw_dir))
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  points <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "points.csv"), check.names = FALSE)))
  elements <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "elements.csv"), check.names = FALSE)))
  x_loadings <- as.matrix(suppressWarnings(read.csv(
    file.path(raw_dir, "x_loadings_coefficients.csv"),
    check.names = FALSE
  )))
  if (identical(complete_reducer, "R1-fPLS")) {
    y_loadings <- as.matrix(suppressWarnings(read.csv(file.path(raw_dir, "y_loadings.csv"), check.names = FALSE)))
    beta_coefficients <- setNames(lapply(3:6, function(h) {
      as.matrix(suppressWarnings(read.csv(file.path(raw_dir, glue::glue("beta_coefficients_h{h}.csv")), check.names = FALSE)))
    }), as.character(3:6))
    beta_stability_summary <- beta_stability(beta_coefficients, points, elements)
  }

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
    elements = elements,
    require_hard_margin = identical(complete_reducer, "R1-fPLS"),
    compute_classifier_maps = identical(complete_reducer, "R1-fPLS")
  )

  slider_stability <- maximum_margin_summary$spatial_stability[
    maximum_margin_summary$spatial_stability$quantity == "Maximum-margin slider loading" &
      maximum_margin_summary$spatial_stability$retained_components %in% 4:6,
    , drop = FALSE
  ]
  slider_stability <- data.frame(
    reference_components = 3L,
    retained_components = slider_stability$retained_components,
    rho_H = slider_stability$mass_correlation,
    e_H = slider_stability$relative_mass_error,
    reference_mass_norm = slider_stability$reference_mass_norm,
    candidate_mass_norm = slider_stability$candidate_mass_norm,
    sign_alignment = slider_stability$sign_alignment
  )
  write.csv(slider_stability, file.path(aggregate_dir, "slider_stability_by_H.csv"), row.names = FALSE)
  if (!is.null(beta_stability_summary)) {
    write.csv(
      subset(beta_stability_summary$summary, retained_components %in% 4:6),
      file.path(aggregate_dir, "beta_stability_by_H.csv"),
      row.names = FALSE
    )
  }
  slider_plot_data <- rbind(
    data.frame(retained_components = slider_stability$retained_components, metric = "rho_H", value = slider_stability$rho_H),
    data.frame(retained_components = slider_stability$retained_components, metric = "e_H", value = slider_stability$e_H)
  )
  stability_plot <- ggplot(slider_plot_data, aes(retained_components, value, colour = metric)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    facet_wrap(~ metric, scales = "free_y") +
    scale_x_continuous(breaks = 4:6) +
    labs(x = "Retained components H", y = "Comparison with H=3 slider", colour = NULL) +
    theme_bw() +
    theme(legend.position = "none")
  ggsave(
    plot_file(image_dir, "slider_stability_by_H"),
    stability_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )

  functional_mean <- drop(as.matrix(suppressWarnings(read.csv(
    file.path(raw_dir, "functional_mean_locations.csv"), check.names = FALSE
  ))))
  X_fitted <- lapply(seq_len(6L), function(h) {
    X_reconstruction <- as.matrix(suppressWarnings(read.csv(
      file.path(raw_dir, glue::glue("x_hat_locations_h{h}.csv")), check.names = FALSE
    )))
    sweep(X_reconstruction, 2L, functional_mean, "+", check.margin = FALSE)
  })
  Y_fitted <- lapply(seq_len(6L), function(h) {
    as.matrix(suppressWarnings(read.csv(
      file.path(raw_dir, glue::glue("y_hat_h{h}.csv")), check.names = FALSE
    )))
  })
  explained_structure <- observation_explained_structure(
    prepared_data$X, prepared_data$Y, X_fitted, Y_fitted
  )
  write.csv(
    explained_structure,
    file.path(aggregate_dir, "explained_structure_by_H.csv"),
    row.names = FALSE
  )
  explained_labels <- c(
    X_variance_explained = "X variance reconstructed (%)",
    Y_variance_explained = "Y variance reconstructed (%)",
    XY_cross_covariance_explained = "X-Y cross-covariance reconstructed (%)"
  )
  for (metric in names(explained_labels)) {
    plot <- ggplot(
      explained_structure,
      aes(retained_components, 100 * .data[[metric]])
    ) +
      geom_line(linewidth = 0.7, colour = "#007C91") +
      geom_point(size = 2, colour = "#007C91") +
      scale_x_continuous(breaks = 1:6) +
      labs(x = "Retained components H", y = explained_labels[[metric]]) +
      theme_bw()
    ggsave(
      plot_file(image_dir, metric),
      plot,
      width = 7,
      height = 4.5,
      dpi = 180
    )
  }

  if (identical(complete_reducer, "R1-fPLS")) {
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
    if (!is.null(maximum_margin_summary$classifier_maps)) {
      write.csv(
        data.frame(coefficient = drop(maximum_margin_summary$classifier_maps[[as.character(h)]])),
        file.path(map_dir, glue::glue("classifier_coefficient_h{h}.csv")),
        row.names = FALSE
      )
    }
  }

  if (identical(complete_reducer, "R1-fPLS")) {
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
  }

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
    plot_file(image_dir, "maximum_margin_by_H"),
    margin_plot,
    width = 7,
    height = 4.5,
    dpi = 180
  )

}

write_json(
  list(
    schema_version = 2L,
    requested = requested,
    dimension_reducer = complete_reducer,
    run_complete = TRUE,
    status = if (all_gcv_selections_interior) "complete" else "complete_with_GCV_boundary_selection",
    validation_status = unique(vapply(all_evaluations, function(value) {
      as.character(value$provenance$validation_status)
    }, character(1))),
    all_production_GCV_selections_interior = all_gcv_selections_interior,
    first_H_with_perfect_in_sample_separation = if (is.null(separation)) {
      "not_evaluated"
    } else if (any(separation$perfect_separation)) {
      as.character(min(separation$prefix_components[separation$perfect_separation]))
    } else "none_up_to_H6",
    H3_hard_margin_separable = if (is.null(maximum_margin_summary)) {
      "not_evaluated"
    } else isTRUE(maximum_margin_summary$fits[["3"]]$hard_margin),
    prefix_diagnostics = "computed_from_single_H6_fit",
    separation_orientation = list(
      score_positive_class = "CTRL",
      auc_positive_class = "CTRL",
      sensitivity_class = "SCHZ",
      specificity_class = "CTRL"
    ),
    decision_boundary_loading_stability = if (is.null(maximum_margin_summary)) {
      "requires_H6_fit"
    } else {
      list(
        reference = "H3_maximum_margin_SVM_slider_loading",
        comparisons = "H4_to_H6_maximum_margin_SVM_slider_loadings",
        definition = "R_H_times_score_SD_times_unit_standardized_SVM_normal",
        metrics = c("tetrahedral_P1_FEM_mass_correlation_rho_H", "relative_FEM_mass_error_e_H"),
        Gram_Schmidt_rotation = "removed_from_active_analysis"
      )
    },
    explained_structure = if (is.null(maximum_margin_summary)) {
      "requires_H6_fit"
    } else {
      list(
        prefixes = 1:6,
        metrics = c("X_variance_explained", "Y_variance_explained", "XY_cross_covariance_explained"),
        norm = "observation_location_Frobenius_matching_simulation_study",
        FEM_mass_matrix = "not_used"
      )
    },
    beta_stability = if (identical(complete_reducer, "fPCR")) {
      "not_requested_for_fPCR_slider_comparator"
    } else if (is.null(beta_stability_summary)) {
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
        classifier = if (all(maximum_margin_summary$diagnostics$hard_margin)) {
          "linear_C_SVM_cost_1e6_verified_hard_margin"
        } else "linear_C_SVM_cost_1e6_with_recorded_soft_margin_prefixes",
        score_scaling = "componentwise_training_mean_and_standard_deviation_prefix_consistent",
        class_orientation = "positive_is_CTRL_matching_paper_response_coding",
        auc_positive_class = "CTRL",
        sensitivity_class = "SCHZ",
        specificity_class = "CTRL",
        reconstruction_loading = "R_H_times_score_SD_times_unit_standardized_SVM_normal",
        classifier_coefficient = if (identical(complete_reducer, "R1-fPLS")) {
          "W_H_times_inverse_RtW_times_score_space_boundary_normal"
        } else "not_computed_for_fPCR_slider_comparator",
        spatial_metric = "tetrahedral_P1_FEM_mass_correlation_with_H3",
        hard_margin_at_H3 = isTRUE(maximum_margin_summary$fits[["3"]]$hard_margin),
        paraview_bundle = if (identical(complete_reducer, "R1-fPLS")) {
          "aggregate/h_stability/paraview/maximum_margin_comparison.vtu_and_scene_script"
        } else "not_generated_for_fPCR_comparator",
        classifier_formula_max_abs_error_against_native_beta = if (identical(
          complete_reducer, "R1-fPLS"
        )) classifier_formula_max_abs_error else "not_applicable_fPCR"
      )
    },
    distinct_fit_prefix_invariance = "not_applicable_single_progressive_fit",
    complete_data_resources = if (requested %in% c("h_stability", "fpcr_h_stability")) {
      "complete_data_resources.csv"
    } else "not_applicable",
    bootstrap_component_significance = "not_implemented_decision_gated"
  ),
  file.path(aggregate_dir, "application_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("Application aggregation completed.\n")
