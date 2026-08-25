# = ========================================================================== =
# - Script: slider_resampling.R
# - Desc: Training-sample stability of the complete-data H=3 slider loading.
# = ========================================================================== =

evaluate_slider_resampling <- function(model, data, test_options) {
  if (!model$MODE %in% c("R1_fPLS", "fPCR")) stop("unsupported slider-resampling reducer")
  reducer <- if (identical(model$MODE, "fPCR")) "fPCR" else "R1-fPLS"
  if (!is.null(data$cross_validation$test_X) || !is.null(data$cross_validation$test_labels)) {
    stop("slider resampling must not receive omitted-subject predictors or labels")
  }
  if (!identical(model$status, 0L)) {
    return(list(
      failed = TRUE,
      status = model$status,
      dimension_reducer = reducer,
      validation_status = "native_fit_failed"
    ))
  }

  regularization_boundaries <- regularization_boundary_diagnostics(model, test_options)
  report_production_grid_boundaries(
    regularization_boundaries, test_options$provenance$validation_status
  )
  n_comp <- as.integer(test_options$model$n_comp)
  diagnostics <- data.frame(
    component = seq_len(n_comp),
    iterations = as.integer(model$results$iteration_counts),
    monotone = as.logical(model$results$monotone),
    hit_max_iter = as.logical(model$results$hit_max_iter),
    finite_solution = as.logical(model$results$finite_solution)
  )
  if (any(!diagnostics$finite_solution) || any(!diagnostics$monotone)) {
    stop("slider-resampling native fit has a non-finite or non-monotone component")
  }
  if (identical(test_options$provenance$validation_status, "slider_resampling_production") &&
      any(diagnostics$hit_max_iter)) {
    stop("slider-resampling production fit reached the component iteration limit")
  }

  training_mean <- drop(model$results$functional_mean_locations)
  centered_X <- sweep(data$X, 2L, training_mean, check.margin = FALSE)
  projected_scores <- project_reducer_scores(
    centered_X, model$results$X_space_directions, model$results$X_loadings
  )
  projection_error <- max(abs(projected_scores - model$results$X_latent_scores))
  if (!is.finite(projection_error) || projection_error > 1e-9) {
    stop("slider-resampling projection does not reproduce native training scores")
  }

  separation <- do.call(rbind, lapply(seq_len(n_comp), function(h) {
    oriented <- orient_ctrl_scores(data$labels, as.numeric(model$results$Y_hat[[h]]))
    threshold <- best_threshold_metrics(data$labels, oriented$scores)
    data.frame(
      prefix_components = h,
      auc = ctrl_auc(data$labels, oriented$scores),
      sensitivity = threshold[["sensitivity"]],
      specificity = threshold[["specificity"]],
      perfect_separation = threshold[["sensitivity"]] == 1 && threshold[["specificity"]] == 1
    )
  }))
  first_perfect_h <- if (any(separation$perfect_separation)) {
    min(separation$prefix_components[separation$perfect_separation])
  } else NA_integer_

  h3_fit <- fit_maximum_margin_boundary(
    projected_scores[, seq_len(3L), drop = FALSE],
    data$labels,
    cost = test_options$cross_validation$fixed_slider_cost,
    require_hard_margin = FALSE
  )
  slider_h3 <- drop(model$results$X_loadings[, seq_len(3L), drop = FALSE] %*%
    (h3_fit$score_scale * h3_fit$unit_standardized_normal))

  list(
    failed = FALSE,
    status = 0L,
    dimension_reducer = reducer,
    n_comp = n_comp,
    cross_validation = list(
      repeat_index = data$cross_validation$repeat_index,
      fold_index = data$cross_validation$fold_index,
      train_indices = data$cross_validation$train_indices,
      omitted_indices = data$cross_validation$test_indices,
      test_data_used = FALSE
    ),
    separation = separation,
    first_H_with_perfect_training_separation = first_perfect_h,
    h3_hard_margin_separable = isTRUE(h3_fit$hard_margin),
    h3_minimum_canonical_margin = h3_fit$minimum_canonical_margin,
    slider_h3 = slider_h3,
    fixed_slider_cost = test_options$cross_validation$fixed_slider_cost,
    direction_lambda = as.numeric(model$results$direction_lambdas[, 1]),
    loading_lambda = as.numeric(model$results$loading_lambdas[, 1]),
    fpca_lambda = if (is.null(model$results$fpca_lambdas)) {
      rep(NA_real_, n_comp)
    } else as.numeric(model$results$fpca_lambdas[, 1]),
    functional_mean_lambda = model$results$telemetry$mean_selected_lambda,
    regularization_boundaries = regularization_boundaries,
    projection_max_abs_error = projection_error,
    component_diagnostics = diagnostics,
    execution_time = model$results$execution_time,
    peak_ram_mib = model$results$peak_ram_mib,
    provenance = model$results$provenance,
    validation_status = test_options$provenance$validation_status
  )
}

slider_resampling_summary <- function(values) {
  data.frame(
    metric = c("rho_H3", "e_H3"),
    mean = c(mean(values$mass_correlation), mean(values$relative_mass_error)),
    sd = c(sd(values$mass_correlation), sd(values$relative_mass_error)),
    median = c(median(values$mass_correlation), median(values$relative_mass_error)),
    q25 = c(
      unname(quantile(values$mass_correlation, 0.25)),
      unname(quantile(values$relative_mass_error, 0.25))
    ),
    q75 = c(
      unname(quantile(values$mass_correlation, 0.75)),
      unname(quantile(values$relative_mass_error, 0.75))
    ),
    minimum = c(min(values$mass_correlation), min(values$relative_mass_error)),
    maximum = c(max(values$mass_correlation), max(values$relative_mass_error)),
    training_fits = nrow(values)
  )
}

aggregate_slider_resampling <- function(evaluations, aggregate_dir, image_dir, cfg) {
  dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
  reducers <- unique(vapply(evaluations, function(value) value$dimension_reducer, character(1)))
  if (length(reducers) != 1L || !reducers %in% c("R1-fPLS", "fPCR")) {
    stop("slider resampling must aggregate exactly one supported dimension reducer")
  }
  reducer <- reducers[[1]]
  reference_target <- if (identical(reducer, "fPCR")) "fpcr_h_stability" else "h_stability"
  reference_status_file <- file.path(
    cfg$PATH_RESULTS, "brain", "aggregate", reference_target, "application_run_status.json"
  )
  reference_file <- file.path(
    cfg$PATH_RESULTS, "brain", "aggregate", reference_target, "maximum_margin_maps",
    "reconstruction_loading_h3.csv"
  )
  if (!file.exists(reference_status_file) || !file.exists(reference_file)) {
    stop("slider resampling requires the complete-data status and H=3 slider map")
  }
  reference_status <- jsonlite::fromJSON(reference_status_file, simplifyVector = TRUE)
  reference_validation <- as.character(reference_status$validation_status)
  accepted_status <- length(reference_status$status) == 1L && reference_status$status %in% c(
    "complete", "complete_with_GCV_boundary_selection"
  )
  reducer_matches <- is.null(reference_status$dimension_reducer) ||
    identical(as.character(reference_status$dimension_reducer), reducer)
  fpls_h3_matches <- !identical(reducer, "R1-fPLS") ||
    identical(as.character(reference_status$first_H_with_perfect_in_sample_separation), "3")
  if (!isTRUE(reference_status$run_complete) || !accepted_status ||
      !identical(reference_validation, "complete_data_production") ||
      !reducer_matches || !fpls_h3_matches) {
    stop("slider resampling requires its accepted production complete-data reference")
  }
  reference <- matrix(as.numeric(read.csv(reference_file, check.names = FALSE)[[1]]), ncol = 1L)
  reference_md5 <- unname(as.character(tools::md5sum(reference_file)))
  mesh <- load_brain_mesh(cfg$PATH_APPLICATION_DATA)
  if (nrow(reference) != nrow(mesh$nodes) || any(!is.finite(reference))) {
    stop("complete-data H=3 slider map is incompatible with the configured brain mesh")
  }
  elements <- matrix(as.integer(mesh$elements), ncol = 4L)
  volumes <- tetrahedral_volumes(mesh$nodes, elements)

  fold_diagnostics <- do.call(rbind, lapply(evaluations, function(value) {
    data.frame(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      training_subjects = length(value$cross_validation$train_indices),
      omitted_subjects = length(value$cross_validation$omitted_indices),
      test_data_used = value$cross_validation$test_data_used,
      first_H_with_perfect_training_separation = value$first_H_with_perfect_training_separation,
      h3_hard_margin_separable = value$h3_hard_margin_separable,
      h3_minimum_canonical_margin = value$h3_minimum_canonical_margin,
      projection_max_abs_error = value$projection_max_abs_error
    )
  }))
  maximum_H <- max(vapply(evaluations, function(value) value$n_comp, integer(1)))
  hmin_label <- ifelse(
    is.na(fold_diagnostics$first_H_with_perfect_training_separation),
    paste0(">", maximum_H),
    as.character(fold_diagnostics$first_H_with_perfect_training_separation)
  )
  hmin_distribution <- as.data.frame(table(hmin_label), stringsAsFactors = FALSE)
  names(hmin_distribution) <- c("first_H", "training_fits")
  hmin_distribution$proportion <- hmin_distribution$training_fits / nrow(fold_diagnostics)

  comparisons <- do.call(rbind, lapply(evaluations, function(value) {
    candidate <- matrix(value$slider_h3, ncol = 1L)
    comparison <- mass_stability(reference, candidate, elements, volumes, sign_align = FALSE)
    cbind(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      dimension_reducer = reducer,
      reference_components = 3L,
      retained_components = 3L,
      comparison
    )
  }))
  summary <- slider_resampling_summary(comparisons)

  regularization_boundaries <- do.call(rbind, lapply(evaluations, function(value) {
    cbind(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      value$regularization_boundaries
    )
  }))
  resources <- do.call(rbind, lapply(evaluations, function(value) {
    diagnostics <- value$component_diagnostics
    data.frame(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      wall_seconds = as.numeric(value$execution_time),
      peak_ram_mib = value$peak_ram_mib,
      max_component_iterations = max(diagnostics$iterations),
      any_component_hit_max_iter = any(diagnostics$hit_max_iter),
      all_components_monotone = all(diagnostics$monotone),
      all_components_finite = all(diagnostics$finite_solution)
    )
  }))

  write.csv(fold_diagnostics, file.path(aggregate_dir, "slider_resampling_fold_diagnostics.csv"), row.names = FALSE)
  write.csv(hmin_distribution, file.path(aggregate_dir, "slider_resampling_Hmin_distribution.csv"), row.names = FALSE)
  write.csv(comparisons, file.path(aggregate_dir, "slider_resampling_vs_complete_H3.csv"), row.names = FALSE)
  write.csv(summary, file.path(aggregate_dir, "slider_resampling_summary.csv"), row.names = FALSE)
  write.csv(
    regularization_boundaries,
    file.path(aggregate_dir, "slider_resampling_regularization_boundary_diagnostics.csv"),
    row.names = FALSE
  )
  write.csv(resources, file.path(aggregate_dir, "slider_resampling_resources.csv"), row.names = FALSE)

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  plot_values <- rbind(
    data.frame(metric = "rho_H3", value = comparisons$mass_correlation),
    data.frame(metric = "e_H3", value = comparisons$relative_mass_error)
  )
  stability_plot <- ggplot(plot_values, aes(metric, value, colour = metric)) +
    geom_boxplot(width = 0.3, outlier.shape = NA) +
    geom_jitter(width = 0.08, height = 0, alpha = 0.65) +
    facet_wrap(~ metric, scales = "free_y") +
    labs(x = NULL, y = paste(reducer, "training-fit comparison with complete-data H=3 slider")) +
    theme_bw() +
    theme(legend.position = "none")
  ggsave(plot_file(image_dir, "slider_resampling_vs_complete_H3"), stability_plot, width = 7, height = 4.5, dpi = 180)

  hmin_plot <- ggplot(hmin_distribution, aes(first_H, proportion)) +
    geom_col(fill = "#007C91") +
    scale_y_continuous(limits = c(0, 1)) +
    labs(x = "First H with perfect training separation", y = "Proportion of training fits") +
    theme_bw()
  ggsave(plot_file(image_dir, "slider_resampling_Hmin_distribution"), hmin_plot, width = 7, height = 4.5, dpi = 180)

  list(
    repeats = length(unique(fold_diagnostics$repeat_index)),
    folds = length(unique(fold_diagnostics$fold_index)),
    fits = nrow(fold_diagnostics),
    comparable_H3_fits = nrow(comparisons),
    dimension_reducer = reducer,
    complete_data_reference_target = reference_target,
    complete_data_reference_status = reference_status$status,
    complete_data_reference_first_H = reference_status$first_H_with_perfect_in_sample_separation,
    complete_data_reference_H3_hard_margin = reference_status$H3_hard_margin_separable,
    complete_data_reference_map_md5 = reference_md5,
    all_test_data_unused = all(!fold_diagnostics$test_data_used),
    all_H3_hard_margin_separable = all(fold_diagnostics$h3_hard_margin_separable),
    Hmin_distribution = hmin_distribution,
    comparisons = comparisons,
    summary = summary,
    all_GCV_selections_interior = !any(
      regularization_boundaries$selected_at_lower_boundary |
        regularization_boundaries$selected_at_upper_boundary
    )
  )
}
