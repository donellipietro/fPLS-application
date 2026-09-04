# = ========================================================================== =
# - Script: projection.R
# - Desc: Sequential projection onto fitted reducer directions and loadings.
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
