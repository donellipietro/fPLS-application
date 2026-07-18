# = ========================================================================== =
# - Script: error_metrics.R
# - Desc: Utility functions for norms, error metrics, and functional angles.
# = ========================================================================== =


## Function: norm_l2
# - Args:
#   * x: numeric vector or matrix
# - Desc:
#   Computes the Euclidean (l2) norm of 'x' using t(x) %*% x.
norm_l2 <- function(x) {
  return(sqrt(as.numeric(t(x) %*% x)))
}


## Function: norm_A
# - Args:
#   * x: numeric vector
#   * A: symmetric positive-definite matrix defining the inner product
# - Desc:
#   Computes the l2 norm in the metric induced by 'A': sqrt(x^T A x).
norm_A <- function(x, A) {
  return(sqrt(as.numeric(t(x) %*% A %*% x)))
}


## Function: RMSE
# - Args:
#   * x: matrix (n_locs x n_stat_unit) of residuals or errors
# - Desc:
#   Computes the root mean squared error over all entries of 'x'.
RMSE <- function(x) {
  ## Coerce to matrix
  x <- as.matrix(x)
  ## Extract dimensions
  n_stat_unit <- ncol(x)
  n_locs <- nrow(x)
  ## Return RMSE
  return(sqrt(sum(x^2) / (n_stat_unit * n_locs)))
}


## Function: IRMSE
# - Args:
#   * x: matrix (n_nodes x n_stat_unit) of residual fields
#   * R0: mass matrix
# - Desc:
#   Computes the integrated RMSE using the inner product induced by R0:
#   sqrt(trace(X^T R0 X) / n_stat_unit).
IRMSE <- function(x, R0) {
  ## Coerce to matrix
  x <- as.matrix(x)
  ## Extract number of statistical units
  n_stat_unit <- ncol(x)
  ## Return integrated RMSE
  return(sqrt(sum(diag(t(x) %*% R0 %*% x)) / n_stat_unit))
}


## Function: angle_between_functions
# - Args:
#   * f1, f2: numeric vectors (functions discretized on nodes)
#   * R0: mass matrix
# - Desc:
#   Computes the angle (in radians) between 'f1' and 'f2' under the
#   inner product induced by R0:
#   acos((f1^T R0 f2) / (||f1|| * ||f2||)).
angle_between_functions <- function(f1, f2, R0) {
  ## Compute norms under R0
  norm_f1 <- sqrt(as.numeric(t(f1) %*% R0 %*% f1))
  norm_f2 <- sqrt(as.numeric(t(f2) %*% R0 %*% f2))
  ## Compute inner product
  f1_dot_f2 <- as.numeric(t(f1) %*% R0 %*% f2)
  ## Return angle in radians
  return(acos(f1_dot_f2 / (norm_f1 * norm_f2)))
}