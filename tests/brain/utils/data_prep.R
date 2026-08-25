# = ========================================================================== =
# - Script: data_prep.R
# - Desc: Loads raw brain inputs; native fits estimate the functional mean.
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

brain_input_md5 <- function(data_dir) {
  assert_brain_data_available(data_dir)
  files <- required_brain_files(data_dir)
  signature <- setNames(as.character(tools::md5sum(files)), basename(files))
  if (anyNA(signature)) stop("Could not compute the application input MD5 signature")
  signature
}

brain_preprocessing_md5 <- function() {
  file <- normalizePath("tests/brain/utils/data_prep.R", mustWork = TRUE)
  unname(as.character(tools::md5sum(file)))
}

load_brain_mesh <- function(data_dir) {
  assert_brain_data_available(data_dir)
  mesh <- readRDS(file.path(data_dir, "FEMbasis.Rds"))$mesh
  list(
    nodes = as.matrix(mesh$nodes),
    elements = as.matrix(mesh$tetrahedrons),
    boundary = matrix(as.integer(mesh$nodesmarkers), ncol = 1L)
  )
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

load_brain_application_data <- function(data_dir, input_md5 = brain_input_md5(data_dir)) {
  assert_brain_data_available(data_dir)

  mesh <- load_brain_mesh(data_dir)
  X <- as.matrix(readRDS(file.path(data_dir, "X_imputed.rds")))
  storage.mode(X) <- "double"
  response <- recoded_response(readRDS(file.path(data_dir, "Ycl.rds"))[, 1])

  nodes <- mesh$nodes
  elements <- mesh$elements
  boundary <- mesh$boundary
  if (ncol(nodes) != 3L || ncol(elements) != 4L) {
    stop("Expected a volumetric tetrahedral brain mesh")
  }
  if (ncol(X) != nrow(nodes)) {
    stop(glue::glue("X has {ncol(X)} columns but mesh has {nrow(nodes)} nodes"))
  }

  list(
    X = X,
    Y = response$y,
    labels = response$labels,
    counts = response$counts,
    nodes = nodes,
    elements = elements,
    boundary = boundary,
    input_md5 = input_md5,
    preprocessing_md5 = brain_preprocessing_md5(),
    centering = "overall_gcv_smoothed_functional_mean",
    dimensions = list(
      n_subjects = nrow(X),
      n_nodes = ncol(X),
      n_tetrahedra = nrow(elements)
    )
  )
}

stratified_fold_ids <- function(labels, n_folds, repeat_index, seed = 0L) {
  labels <- factor(as.character(labels), levels = c("CTRL", "SCHZ"))
  n_folds <- as.integer(n_folds)
  if (n_folds < 2L || any(table(labels) < n_folds)) {
    stop("stratified CV requires at least one subject per class in every fold")
  }

  set.seed(as.integer(seed) + as.integer(repeat_index) - 1L)
  fold_ids <- integer(length(labels))
  for (label in levels(labels)) {
    indices <- sample(which(labels == label))
    fold_ids[indices] <- rep(seq_len(n_folds), length.out = length(indices))
  }
  fold_ids
}

prepare_brain_cv_split <- function(
    data, n_folds, repeat_index, fold_index, seed = 0L, include_omitted_data = TRUE) {
  fold_ids <- stratified_fold_ids(data$labels, n_folds, repeat_index, seed)
  test_indices <- which(fold_ids == as.integer(fold_index))
  train_indices <- which(fold_ids != as.integer(fold_index))
  train_response <- recoded_response(data$labels[train_indices])
  split <- list(
    X = data$X[train_indices, , drop = FALSE],
    Y = train_response$y,
    labels = train_response$labels,
    counts = train_response$counts,
    nodes = data$nodes,
    elements = data$elements,
    boundary = data$boundary,
    input_md5 = data$input_md5,
    preprocessing_md5 = data$preprocessing_md5,
    centering = "training_overall_gcv_smoothed_functional_mean",
    dimensions = list(
      n_subjects = length(train_indices),
      n_nodes = ncol(data$X),
      n_tetrahedra = nrow(data$elements)
    ),
    cross_validation = list(
      n_folds = as.integer(n_folds),
      repeat_index = as.integer(repeat_index),
      fold_index = as.integer(fold_index),
      seed = as.integer(seed),
      train_indices = train_indices,
      test_indices = test_indices,
      test_counts = table(factor(as.character(data$labels[test_indices]), levels = c("CTRL", "SCHZ")))
    )
  )
  if (include_omitted_data) {
    split$cross_validation$test_X <- data$X[test_indices, , drop = FALSE]
    split$cross_validation$test_labels <- factor(
      as.character(data$labels[test_indices]), levels = c("CTRL", "SCHZ")
    )
  }
  split
}

write_brain_native_inputs <- function(data, raw_dir) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list(
    X = file.path(raw_dir, "X_raw.csv"),
    Y = file.path(raw_dir, "Y.csv"),
    nodes = file.path(raw_dir, "points.csv"),
    elements = file.path(raw_dir, "elements.csv"),
    boundary = file.path(raw_dir, "boundary.csv")
  )

  write.csv(data$X, files$X, row.names = FALSE)
  write.csv(data$Y, files$Y, row.names = FALSE)
  write.csv(data$nodes, files$nodes, row.names = FALSE)
  write.csv(data$elements, files$elements, row.names = FALSE)
  write.csv(data$boundary, files$boundary, row.names = FALSE)
  files
}
