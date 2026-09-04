# = ========================================================================== =
# - Script: intrinsic_slider.R
# - Desc: Standardized intrinsic fPLS slider in score and loading coordinates.
# = ========================================================================== =

standardized_intrinsic_fpls_slider <- function(scores, x_loadings, y_loadings, h) {
  scores <- as.matrix(scores)[, seq_len(h), drop = FALSE]
  x_loadings <- as.matrix(x_loadings)[, seq_len(h), drop = FALSE]
  y_loadings <- as.numeric(y_loadings)[seq_len(h)]
  score_center <- colMeans(scores)
  score_scale <- apply(scores, 2L, sd)
  response_normal <- score_scale * y_loadings
  response_norm <- sqrt(sum(response_normal^2))
  if (any(!is.finite(score_scale)) || any(score_scale <= 0) ||
      !is.finite(response_norm) || response_norm <= 0) {
    stop("intrinsic fPLS slider requires finite nonconstant scores and response loadings")
  }
  unit_normal <- response_normal / response_norm
  standardized_scores <- sweep(sweep(scores, 2L, score_center, "-"), 2L, score_scale, "/")
  list(
    score_center = score_center,
    score_scale = score_scale,
    unit_standardized_normal = unit_normal,
    coordinate = drop(standardized_scores %*% unit_normal),
    response_norm = response_norm,
    loading = drop(x_loadings %*% (score_scale * unit_normal))
  )
}
