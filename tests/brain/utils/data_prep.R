# = ========================================================================== =
# - Script: data_prep.R
# - Desc: Loads local brain inputs and applies authoritative overall centering.
# = ========================================================================== =

required_brain_files <- function(data_dir) {
  file.path(data_dir, c("FEMbasis.Rds", "X_imputed.rds", "Ycl.rds"))
}

assert_brain_data_available <- function(data_dir) {
  missing <- required_brain_files(data_dir)[!file.exists(required_brain_files(data_dir))]
  if (length(missing) > 0L) {
    stop(glue::glue("Missing local application inputs:\n{paste(missing, collapse = '\n')}"))
  }
}

recoded_response <- function(labels) {
  labels[labels == "CONTROL"] <- "CTRL"
  labels <- factor(labels)
  if (!all(c("CTRL", "SCHZ") %in% levels(labels))) {
    stop("Expected CTRL/SCHZ response labels after recoding CONTROL to CTRL")
  }

  is_ctrl <- labels == "CTRL"
  is_schz <- labels == "SCHZ"
  p_ctrl <- sum(is_ctrl) / length(labels)
  p_schz <- sum(is_schz) / length(labels)
  y <- numeric(length(labels))
  y[is_ctrl] <- sqrt(p_schz / p_ctrl)
  y[is_schz] <- -sqrt(p_ctrl / p_schz)

  list(labels = labels, y = matrix(y, ncol = 1L), counts = table(labels))
}

load_brain_application_data <- function(data_dir) {
  assert_brain_data_available(data_dir)

  basis <- readRDS(file.path(data_dir, "FEMbasis.Rds"))
  X <- as.matrix(readRDS(file.path(data_dir, "X_imputed.rds")))
  storage.mode(X) <- "double"
  response <- recoded_response(readRDS(file.path(data_dir, "Ycl.rds"))[, 1])

  mesh <- basis$mesh
  nodes <- as.matrix(mesh$nodes)
  elements <- as.matrix(mesh$tetrahedrons)
  boundary <- matrix(as.integer(mesh$nodesmarkers), ncol = 1L)
  if (ncol(nodes) != 3L || ncol(elements) != 4L) {
    stop("Expected a volumetric tetrahedral brain mesh")
  }
  if (ncol(X) != nrow(nodes)) {
    stop(glue::glue("X has {ncol(X)} columns but mesh has {nrow(nodes)} nodes"))
  }

  overall_mean <- colMeans(X)
  X_centered <- sweep(X, 2L, overall_mean, check.margin = FALSE)

  list(
    X = X,
    X_centered = X_centered,
    Y = response$y,
    labels = response$labels,
    counts = response$counts,
    nodes = nodes,
    elements = elements,
    boundary = boundary,
    overall_mean = overall_mean,
    centering = "overall_mean",
    dimensions = list(
      n_subjects = nrow(X),
      n_nodes = ncol(X),
      n_tetrahedra = nrow(elements)
    )
  )
}

write_brain_native_inputs <- function(data, raw_dir) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list(
    X = file.path(raw_dir, "X_centered.csv"),
    Y = file.path(raw_dir, "Y.csv"),
    nodes = file.path(raw_dir, "points.csv"),
    elements = file.path(raw_dir, "elements.csv"),
    boundary = file.path(raw_dir, "boundary.csv"),
    mean = file.path(raw_dir, "overall_mean.csv")
  )

  write.csv(data$X_centered, files$X, row.names = FALSE)
  write.csv(data$Y, files$Y, row.names = FALSE)
  write.csv(data$nodes, files$nodes, row.names = FALSE)
  write.csv(data$elements, files$elements, row.names = FALSE)
  write.csv(data$boundary, files$boundary, row.names = FALSE)
  write.csv(matrix(data$overall_mean, nrow = 1L), files$mean, row.names = FALSE)
  files
}
