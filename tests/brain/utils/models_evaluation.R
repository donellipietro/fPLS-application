# = ========================================================================== =
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
  if (!identical(model$status, 0L)) {
    return(list(
      failed = TRUE,
      status = model$status,
      n_comp = test_options$model$n_comp,
      validation_status = "native_fit_failed"
    ))
  }

  n_comp <- test_options$model$n_comp
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
    provenance = model$results$provenance,
    validation_status = test_options$provenance$validation_status
  )
}
