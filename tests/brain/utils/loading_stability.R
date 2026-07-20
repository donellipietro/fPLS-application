# = ========================================================================== =
# - Script: loading_stability.R
# - Desc: FEM mass-metric Procrustes comparison of application X loadings.
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

loading_stability <- function(reference, comparison, points, elements) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  if (any(!is.finite(volumes)) || any(volumes <= 0)) stop("brain mesh has invalid tetrahedral volumes")
  if (!identical(nrow(reference), nrow(comparison)) || ncol(reference) != 3L || ncol(comparison) != 3L) {
    stop("loading stability requires two nodal coefficient matrices with three columns")
  }

  cross <- mass_crossprod(comparison, reference, elements, volumes)
  decomposition <- svd(cross)
  rotation <- decomposition$u %*% t(decomposition$v)
  aligned <- comparison %*% rotation
  difference <- aligned - reference
  reference_norms <- sqrt(diag(mass_crossprod(reference, reference, elements, volumes)))
  aligned_norms <- sqrt(diag(mass_crossprod(aligned, aligned, elements, volumes)))
  difference_norms <- sqrt(diag(mass_crossprod(difference, difference, elements, volumes)))
  inner <- diag(mass_crossprod(aligned, reference, elements, volumes))

  list(
    rotation = rotation,
    per_component = data.frame(
      component = seq_len(3L),
      relative_mass_error = difference_norms / reference_norms,
      mass_correlation = inner / (aligned_norms * reference_norms),
      reference_mass_norm = reference_norms,
      aligned_mass_norm = aligned_norms
    ),
    global_relative_mass_error = sqrt(sum(difference_norms^2) / sum(reference_norms^2)),
    total_volume = sum(volumes)
  )
}
