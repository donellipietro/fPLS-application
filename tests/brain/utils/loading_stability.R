# = ========================================================================== =
# - Script: loading_stability.R
# - Desc: FEM mass-norm helpers and beta stability comparisons.
# = ========================================================================== =

tetrahedral_volumes <- function(points, elements) {
  a <- points[elements[, 2], , drop = FALSE] - points[elements[, 1], , drop = FALSE]
  b <- points[elements[, 3], , drop = FALSE] - points[elements[, 1], , drop = FALSE]
  c <- points[elements[, 4], , drop = FALSE] - points[elements[, 1], , drop = FALSE]
  abs(
    a[, 1] * (b[, 2] * c[, 3] - b[, 3] * c[, 2]) -
      a[, 2] * (b[, 1] * c[, 3] - b[, 3] * c[, 1]) +
      a[, 3] * (b[, 1] * c[, 2] - b[, 2] * c[, 1])
  ) / 6
}

mass_crossprod <- function(left, right, elements, volumes) {
  left_sum <- Reduce(`+`, lapply(seq_len(4L), function(i) left[elements[, i], , drop = FALSE]))
  right_sum <- Reduce(`+`, lapply(seq_len(4L), function(i) right[elements[, i], , drop = FALSE]))
  value <- crossprod(left_sum * volumes, right_sum)
  for (i in seq_len(4L)) {
    value <- value + crossprod(
      left[elements[, i], , drop = FALSE] * volumes,
      right[elements[, i], , drop = FALSE]
    )
  }
  value / 20
}

mass_stability <- function(reference, candidate, elements, volumes, sign_align = FALSE) {
  inner <- drop(mass_crossprod(candidate, reference, elements, volumes))
  sign <- if (sign_align && inner < 0) -1 else 1
  candidate <- sign * candidate
  reference_norm <- sqrt(drop(mass_crossprod(reference, reference, elements, volumes)))
  candidate_norm <- sqrt(drop(mass_crossprod(candidate, candidate, elements, volumes)))
  difference_norm <- sqrt(drop(mass_crossprod(candidate - reference, candidate - reference, elements, volumes)))
  data.frame(
    sign_alignment = sign,
    relative_mass_error = difference_norm / reference_norm,
    mass_correlation = (sign * inner) / (candidate_norm * reference_norm),
    reference_mass_norm = reference_norm,
    candidate_mass_norm = candidate_norm
  )
}

beta_stability <- function(beta_coefficients, points, elements, reference_h = 3L) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  reference <- beta_coefficients[[as.character(reference_h)]]
  comparisons <- lapply(sort(as.integer(names(beta_coefficients))), function(h) {
    cbind(
      retained_components = h,
      mass_stability(reference, beta_coefficients[[as.character(h)]], elements, volumes, sign_align = FALSE)
    )
  })
  list(summary = do.call(rbind, comparisons), total_volume = sum(volumes))
}

observation_explained_structure <- function(X, Y, X_fitted, Y_fitted) {
  if (length(X_fitted) != length(Y_fitted) || length(X_fitted) == 0L) {
    stop("explained-structure reconstructions are incomplete")
  }
  center_columns <- function(values) sweep(as.matrix(values), 2L, colMeans(values), "-")
  variance_explained <- function(observed, fitted) {
    1 - sum((as.matrix(observed) - as.matrix(fitted))^2) /
      sum(center_columns(observed)^2)
  }
  cross_covariance_explained <- function(X, Y, X_hat, Y_hat) {
    observed <- crossprod(center_columns(X), center_columns(Y)) / (nrow(X) - 1L)
    fitted <- crossprod(center_columns(X_hat), center_columns(Y_hat)) / (nrow(X_hat) - 1L)
    1 - sum((observed - fitted)^2) / sum(observed^2)
  }
  result <- do.call(rbind, lapply(seq_along(X_fitted), function(h) {
    data.frame(
      retained_components = h,
      X_variance_explained = variance_explained(X, X_fitted[[h]]),
      Y_variance_explained = variance_explained(Y, Y_fitted[[h]]),
      XY_cross_covariance_explained = cross_covariance_explained(
        X, Y, X_fitted[[h]], Y_fitted[[h]]
      )
    )
  }))
  if (any(!is.finite(as.matrix(result[, -1L, drop = FALSE])))) {
    stop("non-finite explained-structure diagnostic")
  }
  result
}
