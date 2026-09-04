source("tests/brain/utils/data_prep.R")
source("tests/brain/utils/projection.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/intrinsic_slider.R")
source("tests/brain/utils/models_evaluation.R")
source("tests/brain/utils/slider_resampling.R")
suppressMessages(library(ggplot2))
plot_file <- function(directory, stem) file.path(directory, paste0(stem, ".png"))

labels <- factor(rep(c("CTRL", "SCHZ"), each = 4L), levels = c("CTRL", "SCHZ"))
scores <- cbind(
  c(-1, 1, -1, 1, -1, 1, -1, 1),
  c(-2, -1, 1, 2, -2, -1, 1, 2),
  ifelse(labels == "CTRL", 2, -2)
)
model <- list(
  MODE = "R1_fPLS",
  status = 0L,
  results = list(
    functional_mean_locations = matrix(0, 3L, 1L),
    X_space_directions = diag(3),
    X_loadings = diag(3),
    X_latent_scores = scores,
    Y_loadings = matrix(c(0.2, -0.3, 0.5), nrow = 1L),
    Y_hat = list(scores[, 1], scores[, 1] + scores[, 2], scores[, 3]),
    iteration_counts = rep(2L, 3L),
    monotone = rep(TRUE, 3L),
    hit_max_iter = rep(FALSE, 3L),
    finite_solution = rep(TRUE, 3L),
    direction_lambdas = matrix(0.01, 3L, 1L),
    loading_lambdas = matrix(0.01, 3L, 1L),
    telemetry = list(mean_selected_lambda = 0.01),
    execution_time = 1,
    peak_ram_mib = 10,
    provenance = list(validation_status = "slider_resampling_smoke")
  )
)
data <- list(
  X = scores,
  labels = labels,
  resampling = list(
    repeat_index = 1L, fold_index = 1L, train_indices = 1:8, test_indices = 9:10
  )
)
options <- list(
  model = list(n_comp = 3L),
  regularization = list(lambda_grid = c(0.001, 0.01, 0.1)),
  mean_estimation = list(lambda_grid = c(0.001, 0.01, 0.1)),
  provenance = list(validation_status = "slider_resampling_smoke")
)

result <- suppressWarnings(evaluate_slider_resampling(model, data, options))
stopifnot(
  identical(result$first_H_with_perfect_training_separation, 3L),
  identical(length(result$slider_h3), 3L),
  isTRUE(all(is.finite(result$slider_h3))),
  identical(result$resampling$test_data_used, FALSE)
)

response_loadings <- c(0.2, -0.3, 0.5)
score_multipliers <- c(-2, 3, 0.5)
intrinsic <- standardized_intrinsic_fpls_slider(scores, diag(3), response_loadings, 3L)
rescaled <- standardized_intrinsic_fpls_slider(
  sweep(scores, 2L, score_multipliers, "*"),
  sweep(diag(3), 2L, score_multipliers, "/"),
  response_loadings / score_multipliers,
  3L
)
stopifnot(
  isTRUE(all.equal(intrinsic$coordinate, rescaled$coordinate)),
  isTRUE(all.equal(intrinsic$loading, rescaled$loading))
)

summary <- slider_resampling_summary(data.frame(
  mass_correlation = c(0.8, 0.9),
  relative_mass_error = c(0.4, 0.6)
))
stopifnot(
  identical(summary$metric, c("rho_H3", "e_H3")),
  isTRUE(all.equal(summary$median, c(0.85, 0.5)))
)

full_data <- list(
  X = rbind(scores, scores),
  labels = factor(rep(labels, 2L), levels = c("CTRL", "SCHZ")),
  nodes = diag(3),
  elements = matrix(c(1L, 2L, 3L, 1L), nrow = 1L),
  boundary = matrix(0L, 3L, 1L),
  input_md5 = c(input = "x"),
  preprocessing_md5 = "y"
)
training_only <- prepare_brain_resampling_split(full_data, 2L, 1L, 1L, include_omitted_data = FALSE)
stopifnot(
  is.null(training_only$resampling$omitted_X),
  is.null(training_only$resampling$omitted_labels),
  length(training_only$resampling$test_indices) > 0L
)

root <- tempfile("slider-resampling-check-")
reference_dir <- file.path(
  root, "results", "brain", "aggregate", "h_stability", "intrinsic_fpls_slider_maps"
)
dir.create(reference_dir, recursive = TRUE)
jsonlite::write_json(list(
  schema_version = 2L,
  run_complete = TRUE,
  status = "complete",
  validation_status = "complete_data_production",
  first_H_with_perfect_in_sample_separation = "3"
), file.path(dirname(reference_dir), "application_run_status.json"), auto_unbox = TRUE)
write.csv(
  data.frame(coefficient = c(1, 0, 0, 0)),
  file.path(reference_dir, "reconstruction_loading_h3.csv"), row.names = FALSE
)
reference_raw_dir <- file.path(
  root, "results", "brain", "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS"
)
dir.create(reference_raw_dir, recursive = TRUE)
write.csv(
  rbind(c(0, 0, 0), c(1, 0, 0), c(0, 1, 0), c(0, 0, 1)),
  file.path(reference_raw_dir, "points.csv"), row.names = FALSE
)
write.csv(matrix(1:4, nrow = 1L), file.path(reference_raw_dir, "elements.csv"), row.names = FALSE)

evaluation <- result
evaluation$scenario <- "synthetic_r01_f01"
evaluation$slider_h3 <- c(1, 0, 0, 0)
evaluation$regularization_boundaries <- data.frame(
  quantity = "functional mean", component = 1L, selected_lambda = 0.01,
  grid_min = 0.001, grid_max = 0.1,
  selected_at_lower_boundary = FALSE, selected_at_upper_boundary = FALSE
)
evaluation_2 <- evaluation
evaluation_2$scenario <- "synthetic_r01_f02"
evaluation_2$resampling$fold_index <- 2L
aggregated <- aggregate_slider_resampling(
  list(evaluation, evaluation_2),
  file.path(root, "aggregate"), file.path(root, "images"),
  list(PATH_RESULTS = file.path(root, "results"))
)
stopifnot(
  aggregated$fits == 2L,
  aggregated$comparable_H3_fits == 2L,
  isTRUE(aggregated$all_test_data_unused),
  isTRUE(all.equal(aggregated$comparisons$mass_correlation, c(1, 1)))
)
unlink(root, recursive = TRUE)

cat("slider resampling checks passed\n")
