# = ========================================================================== =
# - Script: maximum_margin_stability.R
# - Desc: Maximum-margin classifiers and functional maps for score prefixes.
# = ========================================================================== =

fit_maximum_margin_boundary <- function(scores, labels, cost = 1e6, require_hard_margin = TRUE) {
  if (!requireNamespace("e1071", quietly = TRUE)) {
    stop("maximum-margin sensitivity requires the R package 'e1071'")
  }
  labels <- factor(labels, levels = c("CTRL", "SCHZ"))
  if (nrow(scores) != length(labels) || anyNA(labels) || any(table(labels) == 0L)) {
    stop("maximum-margin sensitivity requires aligned CTRL and SCHZ labels")
  }
  score_center <- colMeans(scores)
  score_scale <- apply(scores, 2, sd)
  if (any(!is.finite(score_scale)) || any(score_scale <= 0)) {
    stop("maximum-margin sensitivity requires nonconstant finite scores")
  }
  standardized <- sweep(sweep(scores, 2, score_center, "-"), 2, score_scale, "/")
  model <- e1071::svm(
    x = standardized,
    y = labels,
    type = "C-classification",
    kernel = "linear",
    cost = cost,
    scale = FALSE,
    tolerance = 1e-10,
    shrinking = FALSE
  )

  standardized_normal <- drop(t(model$coefs) %*% model$SV)
  standardized_intercept <- -drop(model$rho)
  decision <- drop(standardized %*% standardized_normal + standardized_intercept)
  if (mean(decision[labels == "CTRL"]) < mean(decision[labels == "SCHZ"])) {
    standardized_normal <- -standardized_normal
    standardized_intercept <- -standardized_intercept
    decision <- -decision
  }

  class_sign <- ifelse(labels == "CTRL", 1, -1)
  canonical_margins <- class_sign * decision
  hard_margin <- min(canonical_margins) >= 1 - 1e-4
  if (require_hard_margin && !hard_margin) {
    stop("linear SVM did not reach the hard-margin solution at cost = ", cost)
  }

  score_normal <- standardized_normal / score_scale
  score_intercept <- standardized_intercept - sum(standardized_normal * score_center / score_scale)
  score_normal_norm <- sqrt(sum(score_normal^2))
  standardized_normal_norm <- sqrt(sum(standardized_normal^2))
  predicted <- ifelse(decision >= 0, "CTRL", "SCHZ")
  pos <- decision[labels == "CTRL"]
  neg <- decision[labels == "SCHZ"]

  list(
    score_normal = score_normal,
    score_intercept = score_intercept,
    unit_score_normal = score_normal / score_normal_norm,
    score_center = score_center,
    score_scale = score_scale,
    standardized_normal = standardized_normal,
    unit_standardized_normal = standardized_normal / standardized_normal_norm,
    standardized_intercept = standardized_intercept,
    decision = decision,
    signed_distance = decision / standardized_normal_norm,
    geometric_margin = min(canonical_margins) / standardized_normal_norm,
    minimum_canonical_margin = min(canonical_margins),
    hard_margin = hard_margin,
    support_vectors = length(model$index),
    accuracy = mean(predicted == labels),
    sensitivity = mean(predicted[labels == "SCHZ"] == "SCHZ"),
    specificity = mean(predicted[labels == "CTRL"] == "CTRL"),
    auc = mean(outer(pos, neg, FUN = function(left, right) {
      (left > right) + 0.5 * (left == right)
    }))
  )
}

maximum_margin_prefix_sensitivity <- function(
    scores,
    x_loadings,
    x_directions,
    labels,
    points,
    elements,
    reference_h = 3L) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  max_h <- ncol(scores)
  prefixes <- reference_h:max_h
  fits <- setNames(lapply(prefixes, function(h) {
    fit_maximum_margin_boundary(scores[, seq_len(h), drop = FALSE], labels)
  }), prefixes)

  reconstruction_maps <- setNames(lapply(prefixes, function(h) {
    fit <- fits[[as.character(h)]]
    slider_direction <- fit$score_scale * fit$unit_standardized_normal
    x_loadings[, seq_len(h), drop = FALSE] %*% slider_direction
  }), prefixes)
  classifier_maps <- setNames(lapply(prefixes, function(h) {
    directions <- x_directions[, seq_len(h), drop = FALSE]
    loadings <- x_loadings[, seq_len(h), drop = FALSE]
    directions %*% solve(crossprod(loadings, directions), fits[[as.character(h)]]$score_normal)
  }), prefixes)

  reference_fit <- fits[[as.character(reference_h)]]
  reference_predictions <- reference_fit$decision >= 0
  diagnostics <- do.call(rbind, lapply(prefixes, function(h) {
    fit <- fits[[as.character(h)]]
    data.frame(
      retained_components = h,
      geometric_margin_standardized_scores = fit$geometric_margin,
      support_vectors = fit$support_vectors,
      minimum_canonical_margin = fit$minimum_canonical_margin,
      accuracy = fit$accuracy,
      sensitivity = fit$sensitivity,
      specificity = fit$specificity,
      auc = fit$auc,
      decision_correlation_with_H3 = cor(reference_fit$decision, fit$decision),
      prediction_agreement_with_H3 = mean(reference_predictions == (fit$decision >= 0))
    )
  }))
  if (any(diff(diagnostics$geometric_margin_standardized_scores) < -1e-8)) {
    stop("maximum margin decreased after adding a progressive score component")
  }

  spatial_stability <- do.call(rbind, lapply(prefixes, function(h) {
    rbind(
      transform(
        mass_stability(
          reconstruction_maps[[as.character(reference_h)]],
          reconstruction_maps[[as.character(h)]],
          elements,
          volumes
        ),
        retained_components = h,
        quantity = "Maximum-margin slider loading"
      ),
      transform(
        mass_stability(
          classifier_maps[[as.character(reference_h)]],
          classifier_maps[[as.character(h)]],
          elements,
          volumes
        ),
        retained_components = h,
        quantity = "Maximum-margin classifier coefficient"
      )
    )
  }))

  pad <- function(values) c(values, rep(NA_real_, max_h - length(values)))
  boundaries <- do.call(rbind, lapply(prefixes, function(h) {
    fit <- fits[[as.character(h)]]
    row <- data.frame(
      retained_components = h,
      score_intercept = fit$score_intercept,
      standardized_intercept = fit$standardized_intercept
    )
    normals <- unlist(lapply(
      list(
        score_normal = fit$score_normal,
        unit_score_normal = fit$unit_score_normal,
        unit_standardized_normal = fit$unit_standardized_normal,
        score_center = fit$score_center,
        score_scale = fit$score_scale
      ),
      pad
    ))
    names(normals) <- unlist(lapply(
      c(
        "score_normal",
        "unit_score_normal",
        "unit_standardized_normal",
        "score_center",
        "score_scale"
      ),
      function(name) paste0(name, "_t", seq_len(max_h))
    ))
    normals <- as.data.frame(as.list(normals), check.names = FALSE)
    cbind(row, normals)
  }))

  list(
    diagnostics = diagnostics,
    spatial_stability = spatial_stability,
    boundaries = boundaries,
    reconstruction_maps = reconstruction_maps,
    classifier_maps = classifier_maps,
    fits = fits,
    total_volume = sum(volumes)
  )
}
