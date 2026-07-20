# = ========================================================================== =
# - Script: loading_stability.R
# - Desc: Historical latent rotation and FEM mass-norm loading comparisons.
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

rotated_loading_stability <- function(x_loadings, y_loadings, points, elements, reference_h = 3L) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  if (any(!is.finite(volumes)) || any(volumes <= 0)) stop("brain mesh has invalid tetrahedral volumes")
  max_h <- ncol(x_loadings)
  if (reference_h < 1L || reference_h > max_h || ncol(y_loadings) != max_h) {
    stop("rotated loading stability requires matching X/Y loading prefixes")
  }

  rotate_prefix <- function(h) {
    x_loadings[, seq_len(h), drop = FALSE] %*% historical_rotation(as.numeric(y_loadings[1, seq_len(h)]))
  }
  reference <- rotate_prefix(reference_h)[, seq_len(3L), drop = FALSE]
  reference_norms <- sqrt(diag(mass_crossprod(reference, reference, elements, volumes)))
  rotations <- vector("list", max_h - reference_h + 1L)
  names(rotations) <- paste0("H", reference_h:max_h)
  comparisons <- lapply(reference_h:max_h, function(h) {
    rotation <- historical_rotation(as.numeric(y_loadings[1, seq_len(h)]))
    rotations[[paste0("H", h)]] <<- rotation
    candidate <- (x_loadings[, seq_len(h), drop = FALSE] %*% rotation)[, seq_len(3L), drop = FALSE]
    inner <- diag(mass_crossprod(candidate, reference, elements, volumes))
    sign <- ifelse(inner < 0, -1, 1)
    candidate <- sweep(candidate, 2L, sign, `*`)
    difference_norms <- sqrt(diag(mass_crossprod(candidate - reference, candidate - reference, elements, volumes)))
    candidate_norms <- sqrt(diag(mass_crossprod(candidate, candidate, elements, volumes)))
    data.frame(
      retained_components = h,
      loading = seq_len(3L),
      sign_aligned = sign,
      relative_mass_error = difference_norms / reference_norms,
      mass_correlation = abs(inner) / (candidate_norms * reference_norms),
      reference_mass_norm = reference_norms,
      candidate_mass_norm = candidate_norms
    )
  })

  list(
    per_loading = do.call(rbind, comparisons),
    rotations = rotations,
    total_volume = sum(volumes)
  )
}
