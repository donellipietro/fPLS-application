# = ========================================================================== =
# - Script: loading_stability.R
# - Desc: Decision-boundary loading and beta FEM mass-norm comparisons.
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

# Matches analysis/main_CNTRLvsSCHZ.R: Y loadings first, then e2,...,eH.
historical_rotation <- function(y_loadings) {
  h <- length(y_loadings)
  basis <- matrix(0, nrow = h, ncol = h)
  basis[, 1] <- y_loadings / sqrt(sum(y_loadings^2))
  for (i in 2:h) {
    value <- diag(h)[, i]
    for (j in 1:(i - 1L)) value <- value - sum(basis[, j] * value) * basis[, j]
    basis[, i] <- value / sqrt(sum(value^2))
  }
  basis
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

first_rotated_loading_stability <- function(x_loadings, y_loadings, points, elements, reference_h = 3L) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  if (any(!is.finite(volumes)) || any(volumes <= 0)) stop("brain mesh has invalid tetrahedral volumes")
  max_h <- ncol(x_loadings)
  if (reference_h < 1L || reference_h > max_h || ncol(y_loadings) != max_h) {
    stop("rotated loading stability requires matching X/Y loading prefixes")
  }

  first_rotated_loading <- function(h) {
    rotation <- historical_rotation(as.numeric(y_loadings[1, seq_len(h)]))
    x_loadings[, seq_len(h), drop = FALSE] %*% rotation[, 1]
  }
  reference <- first_rotated_loading(reference_h)
  comparisons <- lapply(reference_h:max_h, function(h) {
    cbind(retained_components = h, mass_stability(reference, first_rotated_loading(h), elements, volumes, sign_align = TRUE))
  })

  list(
    summary = do.call(rbind, comparisons),
    reference = reference,
    first_rotation = historical_rotation(as.numeric(y_loadings[1, seq_len(reference_h)]))[, 1],
    total_volume = sum(volumes)
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
