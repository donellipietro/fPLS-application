# = ========================================================================== =

regularization_boundary_diagnostics <- function(model, test_options) {
  rows <- function(quantity, values, grid) {
    values <- as.numeric(values)
    grid <- as.numeric(grid)
    tolerance <- sqrt(.Machine$double.eps)
    data.frame(
      quantity = quantity,
      component = seq_along(values),
      selected_lambda = values,
      grid_min = min(grid),
      grid_max = max(grid),
      selected_at_lower_boundary = abs(values - min(grid)) <= tolerance * abs(min(grid)),
      selected_at_upper_boundary = abs(values - max(grid)) <= tolerance * abs(max(grid))
    )
  }

  model_rows <- if (identical(model$MODE, "fPCR")) {
    rows("fPCA loading", model$results$fpca_lambdas[, 1], test_options$regularization$lambda_grid)
  } else {
    rbind(
      rows("fPLS direction", model$results$direction_lambdas[, 1], test_options$regularization$lambda_grid),
      rows("fPLS loading", model$results$loading_lambdas[, 1], test_options$regularization$lambda_grid)
    )
  }
  rbind(
    rows(
      "functional mean",
      model$results$telemetry$mean_selected_lambda,
      test_options$mean_estimation$lambda_grid
    ),
    model_rows
  )
}

report_production_grid_boundaries <- function(diagnostics, validation_status) {
  production <- validation_status %in% c(
    "complete_data_production", "complete_data_exploratory_diagnostic",
    "cross_validation_production", "slider_resampling_production"
  )
  boundary <- diagnostics$selected_at_lower_boundary | diagnostics$selected_at_upper_boundary
  if (production && any(boundary)) {
    hits <- diagnostics[boundary, c("quantity", "component", "selected_lambda", "grid_min", "grid_max")]
    warning(
      "production GCV selected a grid boundary; run continues for curve inspection:\n",
      paste(capture.output(print(hits, row.names = FALSE)), collapse = "\n"),
      call. = FALSE
    )
  }
  invisible(diagnostics)
}
# - Script: models_evaluation.R
# - Desc: Application separation diagnostics for sequential component prefixes.
# = ========================================================================== =

ctrl_auc <- function(labels, scores) {
  labels <- as.character(labels)
  pos <- scores[labels == "CTRL"]
  neg <- scores[labels == "SCHZ"]
  if (length(pos) == 0L || length(neg) == 0L) return(NaN)
  mean(outer(pos, neg, FUN = function(a, b) (a > b) + 0.5 * (a == b)))
}

best_threshold_metrics <- function(labels, scores) {
  labels <- as.character(labels)
  candidates <- sort(unique(scores))
  if (length(candidates) == 0L) {
    return(c(threshold = NaN, sensitivity = NaN, specificity = NaN))
  }
  metrics <- t(vapply(candidates, function(threshold) {
    predicted <- ifelse(scores >= threshold, "CTRL", "SCHZ")
    sensitivity <- mean(predicted[labels == "SCHZ"] == "SCHZ")
    specificity <- mean(predicted[labels == "CTRL"] == "CTRL")
    c(threshold = threshold, sensitivity = sensitivity, specificity = specificity)
  }, numeric(3)))
  metrics[which.max(metrics[, "sensitivity"] + metrics[, "specificity"]), ]
}

orient_ctrl_scores <- function(labels, scores) {
  raw_auc <- ctrl_auc(labels, scores)
  if (is.finite(raw_auc) && raw_auc < 0.5) {
    return(list(scores = -scores, sign_flipped = TRUE))
  }
  list(scores = scores, sign_flipped = FALSE)
}

evaluate_results <- function(model, data, test_options) {
  if (isTRUE(test_options$cross_validation$enabled) && identical(
    test_options$cross_validation$purpose, "interpretive_slider_stability"
  )) {
    return(evaluate_slider_resampling(model, data, test_options))
  }
  if (isTRUE(test_options$cross_validation$enabled)) {
    return(evaluate_cv_model(model, data, test_options))
  }
  if (!identical(model$status, 0L)) {
    return(list(
      failed = TRUE,
      status = model$status,
      n_comp = test_options$model$n_comp,
      validation_status = "native_fit_failed"
    ))
  }

  n_comp <- test_options$model$n_comp
  regularization_boundaries <- regularization_boundary_diagnostics(model, test_options)
  report_production_grid_boundaries(regularization_boundaries, test_options$provenance$validation_status)
  separation <- do.call(rbind, lapply(seq_len(n_comp), function(h) {
    oriented <- orient_ctrl_scores(data$labels, as.numeric(model$results$Y_hat[[h]]))
    scores <- oriented$scores
    threshold <- best_threshold_metrics(data$labels, scores)
    data.frame(
      prefix_components = h,
      auc = ctrl_auc(data$labels, scores),
      sign_flipped = oriented$sign_flipped,
      threshold = threshold[["threshold"]],
      sensitivity = threshold[["sensitivity"]],
      specificity = threshold[["specificity"]]
    )
  }))
  separation$perfect_separation <- separation$sensitivity == 1 & separation$specificity == 1

  list(
    failed = FALSE,
    status = 0L,
    n_comp = n_comp,
    separation = separation,
    execution_time = model$results$execution_time,
    peak_ram_mib = model$results$peak_ram_mib,
    iteration_count = model$results$iteration_counts,
    monotone = model$results$monotone,
    objective = model$results$objective,
    hit_max_iter = model$results$hit_max_iter,
    finite_solution = model$results$finite_solution,
    direction_lambda = model$results$direction_lambdas[, 1],
    loading_lambda = model$results$loading_lambdas[, 1],
    fpls_loading_gcv = model$results$fpls_loading_gcv,
    fpca_gcv = model$results$fpca_gcv,
    regularization_boundaries = regularization_boundaries,
    provenance = model$results$provenance,
    validation_status = test_options$provenance$validation_status
  )
}
