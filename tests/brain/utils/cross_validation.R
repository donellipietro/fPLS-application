# = ========================================================================== =
# - Script: cross_validation.R
# - Desc: Leakage-safe held-out projection, classification, and metrics.
# = ========================================================================== =

project_reducer_scores <- function(X_centered, directions, loadings) {
  residual <- X_centered
  scores <- matrix(0, nrow(X_centered), ncol(directions))
  for (component in seq_len(ncol(directions))) {
    scores[, component] <- drop(residual %*% directions[, component])
    residual <- residual - scores[, component] %*% t(loadings[, component])
  }
  scores
}

schz_auc <- function(labels, ctrl_score) {
  schz <- -ctrl_score[labels == "SCHZ"]
  ctrl <- -ctrl_score[labels == "CTRL"]
  mean(outer(schz, ctrl, function(left, right) (left > right) + 0.5 * (left == right)))
}

schz_average_precision <- function(labels, ctrl_score) {
  truth <- labels == "SCHZ"
  schz_score <- -ctrl_score
  order_index <- order(schz_score, decreasing = TRUE)
  ordered_truth <- truth[order_index]
  if (!any(ordered_truth)) return(NaN)
  threshold_ends <- cumsum(rle(schz_score[order_index])$lengths)
  true_positives <- cumsum(ordered_truth)[threshold_ends]
  precision <- true_positives / threshold_ends
  recall_increment <- diff(c(0, true_positives)) / sum(ordered_truth)
  sum(precision * recall_increment)
}

classification_metrics <- function(labels, ctrl_score, threshold = 0, predicted = NULL) {
  labels <- factor(as.character(labels), levels = c("CTRL", "SCHZ"))
  if (is.null(predicted)) predicted <- ifelse(ctrl_score >= threshold, "CTRL", "SCHZ")
  predicted <- factor(predicted, levels = c("CTRL", "SCHZ"))
  tp <- sum(predicted == "SCHZ" & labels == "SCHZ")
  tn <- sum(predicted == "CTRL" & labels == "CTRL")
  fp <- sum(predicted == "SCHZ" & labels == "CTRL")
  fn <- sum(predicted == "CTRL" & labels == "SCHZ")
  sensitivity <- tp / (tp + fn)
  specificity <- tn / (tn + fp)
  denominator <- sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn))

  data.frame(
    n = length(labels),
    n_ctrl = sum(labels == "CTRL"),
    n_schz = sum(labels == "SCHZ"),
    accuracy = mean(predicted == labels),
    sensitivity_schz = sensitivity,
    specificity_ctrl = specificity,
    balanced_accuracy = 0.5 * (sensitivity + specificity),
    roc_auc_schz = schz_auc(labels, ctrl_score),
    average_precision_schz = schz_average_precision(labels, ctrl_score),
    mcc = if (denominator > 0) (tp * tn - fp * fn) / denominator else 0,
    degenerate_prediction = denominator == 0,
    true_schz = tp,
    true_ctrl = tn,
    false_schz = fp,
    false_ctrl = fn
  )
}

training_threshold <- function(labels, ctrl_score) {
  values <- sort(unique(ctrl_score))
  span <- max(1, diff(range(values)))
  candidates <- c(
    values[1] - span,
    if (length(values) > 1L) head(values, -1L) + diff(values) / 2,
    values[length(values)] + span
  )
  balanced_accuracy <- vapply(candidates, function(value) {
    classification_metrics(labels, ctrl_score, value)$balanced_accuracy
  }, numeric(1))
  best <- which(abs(balanced_accuracy - max(balanced_accuracy)) < 1e-12)
  candidates[best[ceiling(length(best) / 2)]]
}

fit_balanced_linear_svm <- function(scores, labels, cost) {
  if (!requireNamespace("e1071", quietly = TRUE)) stop("CV requires the R package 'e1071'")
  labels <- factor(as.character(labels), levels = c("CTRL", "SCHZ"))
  center <- colMeans(scores)
  scale <- apply(scores, 2, sd)
  if (any(!is.finite(scale)) || any(scale <= 0)) stop("CV SVM received a constant score")
  standardized <- sweep(sweep(scores, 2, center, "-"), 2, scale, "/")
  counts <- table(labels)
  class_weights <- length(labels) / (2 * counts)
  model <- e1071::svm(
    x = standardized,
    y = labels,
    type = "C-classification",
    kernel = "linear",
    cost = cost,
    class.weights = class_weights,
    scale = FALSE,
    tolerance = 1e-10,
    shrinking = FALSE
  )
  normal <- drop(t(model$coefs) %*% model$SV)
  intercept <- -drop(model$rho)
  decision <- drop(standardized %*% normal + intercept)
  if (mean(decision[labels == "CTRL"]) < mean(decision[labels == "SCHZ"])) {
    normal <- -normal
    intercept <- -intercept
    decision <- -decision
  }
  normal_norm <- sqrt(sum(normal^2))
  if (!is.finite(normal_norm) || normal_norm <= 0) stop("CV SVM produced a zero normal")

  list(
    center = center,
    scale = scale,
    normal = normal,
    unit_normal = normal / normal_norm,
    intercept = intercept,
    normal_norm = normal_norm,
    decision = decision,
    cost = cost,
    class_weights = class_weights
  )
}

predict_balanced_linear_svm <- function(fit, scores) {
  standardized <- sweep(sweep(scores, 2, fit$center, "-"), 2, fit$scale, "/")
  drop(standardized %*% fit$normal + fit$intercept)
}

tune_balanced_linear_svm <- function(scores, labels, costs, n_folds, seed) {
  n_folds <- min(as.integer(n_folds), min(table(labels)))
  fold_ids <- stratified_fold_ids(labels, n_folds, repeat_index = 1L, seed = seed)
  results <- do.call(rbind, lapply(costs, function(cost) {
    fold_values <- vapply(seq_len(n_folds), function(fold) {
      train <- fold_ids != fold
      fit <- fit_balanced_linear_svm(scores[train, , drop = FALSE], labels[train], cost)
      decision <- predict_balanced_linear_svm(fit, scores[!train, , drop = FALSE])
      classification_metrics(labels[!train], decision)$balanced_accuracy
    }, numeric(1))
    data.frame(cost = cost, mean_balanced_accuracy = mean(fold_values), sd_balanced_accuracy = sd(fold_values))
  }))
  best <- results$mean_balanced_accuracy == max(results$mean_balanced_accuracy)
  selected_cost <- min(results$cost[best])
  list(cost = selected_cost, results = results)
}

evaluate_cv_model <- function(model, data, test_options) {
  reducer <- model$MODE
  if (!reducer %in% c("R1_fPLS", "fPCR")) stop("unsupported dimension reducer")
  reducer_label <- if (reducer == "fPCR") "fPCR" else "R1-fPLS"
  if (!identical(model$status, 0L)) {
    return(list(
      failed = TRUE,
      status = model$status,
      dimension_reducer = reducer_label,
      validation_status = "native_fit_failed"
    ))
  }
  regularization_boundaries <- regularization_boundary_diagnostics(model, test_options)
  report_production_grid_boundaries(regularization_boundaries, test_options$provenance$validation_status)
  cv <- data$cross_validation
  components <- as.integer(test_options$cross_validation$evaluation_components)
  directions <- model$results$X_space_directions
  loadings <- model$results$X_loadings
  training_mean <- drop(model$results$functional_mean_locations)
  train_X_centered <- sweep(data$X, 2L, training_mean, check.margin = FALSE)
  test_X_centered <- sweep(cv$test_X, 2L, training_mean, check.margin = FALSE)
  train_scores <- project_reducer_scores(train_X_centered, directions, loadings)
  test_scores <- project_reducer_scores(test_X_centered, directions, loadings)
  projection_error <- max(abs(train_scores - model$results$X_latent_scores))
  if (!is.finite(projection_error) || projection_error > 1e-9) {
    stop(reducer_label, " held-out projection does not reproduce native training scores")
  }
  diagnostics <- data.frame(
    component = seq_len(test_options$model$n_comp),
    iterations = as.integer(model$results$iteration_counts),
    monotone = as.logical(model$results$monotone),
    hit_max_iter = as.logical(model$results$hit_max_iter),
    finite_solution = as.logical(model$results$finite_solution)
  )
  if (any(!diagnostics$finite_solution) || any(!diagnostics$monotone)) {
    stop(reducer_label, " native fit has a non-finite or non-monotone component")
  }
  if (identical(test_options$provenance$validation_status, "cross_validation_production") &&
      any(diagnostics$hit_max_iter)) {
    stop(reducer_label, " production fit reached the component iteration limit")
  }

  metrics <- list()
  predictions <- list()
  tuning <- list()
  response_maps <- list()
  svm_maps <- list()
  row <- 0L
  for (h in components) {
    prefix_scores <- train_scores[, seq_len(h), drop = FALSE]
    coefficients <- qr.solve(prefix_scores, data$Y)
    if (any(!is.finite(coefficients))) stop(reducer_label, " latent-response OLS is non-finite")
    coefficient_norm <- sqrt(sum(coefficients^2))
    if (!is.finite(coefficient_norm) || coefficient_norm <= 0) {
      stop(reducer_label, " latent-response OLS produced a zero normal")
    }
    train_response <- drop(prefix_scores %*% coefficients)
    test_response <- drop(test_scores[, seq_len(h), drop = FALSE] %*% coefficients)
    threshold <- training_threshold(data$labels, train_response)
    train_scale <- sd(train_response)
    if (!is.finite(train_scale) || train_scale <= 0) stop("reconstructed response is constant")
    test_response_margin <- (test_response - threshold) / train_scale

    row <- row + 1L
    metrics[[row]] <- cbind(
      dimension_reducer = reducer_label,
      classifier = "Latent response",
      retained_components = h,
      sample = "train",
      selected_cost = NA_real_,
      threshold = threshold,
      classification_metrics(data$labels, train_response, threshold)
    )
    row <- row + 1L
    metrics[[row]] <- cbind(
      dimension_reducer = reducer_label,
      classifier = "Latent response",
      retained_components = h,
      sample = "test",
      selected_cost = NA_real_,
      threshold = threshold,
      classification_metrics(cv$test_labels, test_response, threshold)
    )
    predictions[[length(predictions) + 1L]] <- data.frame(
      subject_index = cv$test_indices,
      actual = as.character(cv$test_labels),
      predicted = ifelse(test_response >= threshold, "CTRL", "SCHZ"),
      dimension_reducer = reducer_label,
      classifier = "Latent response",
      retained_components = h,
      ctrl_score = test_response,
      classification_margin = test_response_margin
    )

    tuning_result <- tune_balanced_linear_svm(
      train_scores[, seq_len(h), drop = FALSE],
      data$labels,
      as.numeric(test_options$cross_validation$svm_cost_grid),
      test_options$cross_validation$inner_folds,
      seed = test_options$cross_validation$seed +
        1000L * cv$repeat_index + 10L * cv$fold_index + h
    )
    svm <- fit_balanced_linear_svm(
      train_scores[, seq_len(h), drop = FALSE],
      data$labels,
      tuning_result$cost
    )
    test_svm <- predict_balanced_linear_svm(svm, test_scores[, seq_len(h), drop = FALSE])
    row <- row + 1L
    metrics[[row]] <- cbind(
      dimension_reducer = reducer_label,
      classifier = "Balanced linear SVM",
      retained_components = h,
      sample = "train",
      selected_cost = svm$cost,
      threshold = 0,
      classification_metrics(data$labels, svm$decision)
    )
    row <- row + 1L
    metrics[[row]] <- cbind(
      dimension_reducer = reducer_label,
      classifier = "Balanced linear SVM",
      retained_components = h,
      sample = "test",
      selected_cost = svm$cost,
      threshold = 0,
      classification_metrics(cv$test_labels, test_svm)
    )
    predictions[[length(predictions) + 1L]] <- data.frame(
      subject_index = cv$test_indices,
      actual = as.character(cv$test_labels),
      predicted = ifelse(test_svm >= 0, "CTRL", "SCHZ"),
      dimension_reducer = reducer_label,
      classifier = "Balanced linear SVM",
      retained_components = h,
      ctrl_score = test_svm,
      classification_margin = test_svm / svm$normal_norm
    )
    tuning[[as.character(h)]] <- transform(
      tuning_result$results,
      dimension_reducer = reducer_label,
      classifier = "Balanced linear SVM",
      retained_components = h
    )

    response_normal <- as.numeric(coefficients)
    response_maps[[as.character(h)]] <- drop(
      loadings[, seq_len(h), drop = FALSE] %*% (response_normal / coefficient_norm)
    )
    svm_maps[[as.character(h)]] <- drop(
      loadings[, seq_len(h), drop = FALSE] %*% (svm$scale * svm$unit_normal)
    )
  }

  list(
    failed = FALSE,
    status = 0L,
    dimension_reducer = reducer_label,
    n_comp = test_options$model$n_comp,
    cross_validation = list(
      repeat_index = cv$repeat_index,
      fold_index = cv$fold_index,
      train_indices = cv$train_indices,
      test_indices = cv$test_indices,
      train_counts = as.list(data$counts),
      test_counts = as.list(cv$test_counts)
    ),
    fold_metrics = do.call(rbind, metrics),
    predictions = do.call(rbind, predictions),
    svm_tuning = do.call(rbind, tuning),
    loading_maps = list(
      `Latent response loading` = response_maps,
      `SVM slider loading` = svm_maps
    ),
    direction_lambda = if (is.null(model$results$direction_lambdas)) {
      rep(NA_real_, test_options$model$n_comp)
    } else as.numeric(model$results$direction_lambdas[, 1]),
    loading_lambda = if (is.null(model$results$loading_lambdas)) {
      rep(NA_real_, test_options$model$n_comp)
    } else as.numeric(model$results$loading_lambdas[, 1]),
    fpca_lambda = if (is.null(model$results$fpca_lambdas)) {
      rep(NA_real_, test_options$model$n_comp)
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
