source("tests/brain/utils/data_prep.R")
source("tests/brain/utils/cross_validation.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/maximum_margin_stability.R")
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
  cross_validation = list(
    repeat_index = 1L,
    fold_index = 1L,
    train_indices = 1:8,
    test_indices = 9:10
  )
)
options <- list(
  model = list(n_comp = 3L),
  regularization = list(lambda_grid = c(0.001, 0.01, 0.1)),
  mean_estimation = list(lambda_grid = c(0.001, 0.01, 0.1)),
  cross_validation = list(fixed_slider_cost = 1e6),
  provenance = list(validation_status = "slider_resampling_smoke")
)

result <- suppressWarnings(evaluate_slider_resampling(model, data, options))
stopifnot(
  identical(result$first_H_with_perfect_training_separation, 3L),
  isTRUE(result$h3_hard_margin_separable),
  identical(length(result$slider_h3), 3L),
  isTRUE(all(is.finite(result$slider_h3))),
  identical(result$cross_validation$test_data_used, FALSE)
)

held_out_model <- model
held_out_model$results$Y_loadings <- matrix(c(0, 0, 0.5), nrow = 1L)
held_out_model$results$Y_hat <- list(
  rep(0, nrow(scores)), rep(0, nrow(scores)), 0.5 * scores[, 3]
)
held_out_model$results$provenance$input_md5 <- c(input = "x")
held_out_model$results$provenance$application_commit <- "synthetic-commit"
held_out_data <- list(
  X = rbind(scores, scores[c(1L, 5L), , drop = FALSE]),
  labels = factor(c(as.character(labels), "CTRL", "SCHZ"), levels = c("CTRL", "SCHZ")),
  input_md5 = c(input = "x")
)
held_out_evaluation <- result
held_out_evaluation$provenance$application_commit <- "synthetic-commit"
held_out_evaluation$n_comp <- 3L
held_out_evaluation$cross_validation$train_indices <- 1:8
held_out_evaluation$cross_validation$omitted_indices <- 9:10
held_out <- slider_test_explained_structure(held_out_model, held_out_data, held_out_evaluation)
stopifnot(
  identical(held_out$retained_components, 1:3),
  identical(held_out$test_subjects, rep(2L, 3L)),
  isTRUE(all.equal(held_out$X_variance_explained[3], 1)),
  isTRUE(all.equal(held_out$Y_variance_explained[3], 1)),
  isTRUE(all.equal(held_out$XY_cross_covariance_explained[3], 1))
)

held_out_fpcr_model <- held_out_model
held_out_fpcr_model$MODE <- "fPCR"
training_Y <- recoded_response(held_out_data$labels[1:8])$y
held_out_fpcr_model$results$Y_hat <- lapply(1:3, function(h) {
  scores[, seq_len(h), drop = FALSE] %*%
    qr.solve(scores[, seq_len(h), drop = FALSE], training_Y)
})
held_out_fpcr_evaluation <- held_out_evaluation
held_out_fpcr_evaluation$dimension_reducer <- "fPCR"
held_out_fpcr <- slider_test_explained_structure(
  held_out_fpcr_model, held_out_data, held_out_fpcr_evaluation
)
stopifnot(
  isTRUE(all.equal(held_out_fpcr$Y_variance_explained[3], 1)),
  isTRUE(all.equal(held_out_fpcr$XY_cross_covariance_explained[3], 1))
)

fpcr_model <- model
fpcr_model$MODE <- "fPCR"
fpcr_model$results$fpca_lambdas <- matrix(0.01, 3L, 1L)
fpcr_result <- suppressWarnings(evaluate_slider_resampling(fpcr_model, data, options))
stopifnot(
  identical(fpcr_result$dimension_reducer, "fPCR"),
  identical(length(fpcr_result$slider_h3), 3L),
  isTRUE(all.equal(fpcr_result$fpca_lambda, rep(0.01, 3L)))
)
fpcr_complete <- suppressWarnings(maximum_margin_prefix_sensitivity(
  scores = scores,
  x_loadings = rbind(diag(3), 0),
  x_directions = rbind(diag(3), 0),
  labels = labels,
  points = rbind(c(0, 0, 0), c(1, 0, 0), c(0, 1, 0), c(0, 0, 1)),
  elements = matrix(1:4, nrow = 1L),
  require_hard_margin = FALSE,
  compute_classifier_maps = FALSE
))
stopifnot(
  is.null(fpcr_complete$classifier_maps),
  identical(length(fpcr_complete$reconstruction_maps), 1L),
  isTRUE(fpcr_complete$fits[["3"]]$hard_margin)
)

summary <- slider_resampling_summary(data.frame(
  mass_correlation = c(0.8, 0.9),
  relative_mass_error = c(0.4, 0.6)
))
stopifnot(
  identical(summary$metric, c("rho_H3", "e_H3")),
  isTRUE(all.equal(summary$median, c(0.85, 0.5)))
)

observed_X <- cbind(-2:2, 2:-2)
observed_Y <- matrix(-2:2, ncol = 1L)
explained <- observation_explained_structure(
  observed_X,
  observed_Y,
  list(observed_X, 0.5 * observed_X),
  list(observed_Y, 0.5 * observed_Y)
)
stopifnot(
  isTRUE(all.equal(as.numeric(explained[1, -1L]), c(1, 1, 1))),
  isTRUE(all(is.finite(as.matrix(explained))))
)

root <- tempfile("slider-resampling-check-")
postprocess_evaluation <- held_out_evaluation
postprocess_evaluation$scenario <- "synthetic_r01_f01"
postprocess_evaluation_2 <- postprocess_evaluation
postprocess_evaluation_2$scenario <- "synthetic_r01_f02"
postprocess_evaluation_2$cross_validation$fold_index <- 2L
for (value in list(postprocess_evaluation, postprocess_evaluation_2)) {
  model_dir <- file.path(
    root, "results", "brain", "slider_resampling", value$scenario, "batch_1"
  )
  dir.create(model_dir, recursive = TRUE)
  model_R1_fPLS <- held_out_model
  save(model_R1_fPLS, file = file.path(model_dir, "batch_1_fitted_model_R1_fPLS.RData"))
}
complete_data_dir <- file.path(
  root, "results", "brain", "h_stability", "h_stability_H6", "batch_1"
)
dir.create(complete_data_dir, recursive = TRUE)
saveRDS(held_out_data, file.path(complete_data_dir, "prepared_data.rds"))
postprocessed <- aggregate_slider_test_explained_structure(
  list(postprocess_evaluation, postprocess_evaluation_2),
  "slider_resampling",
  file.path(root, "postprocess_aggregate"),
  file.path(root, "postprocess_images"),
  list(PATH_RESULTS = file.path(root, "results"), PATH_APPLICATION_DATA = "unused")
)
stopifnot(
  nrow(postprocessed$values) == 6L,
  nrow(postprocessed$summary) == 9L,
  identical(postprocessed$native_application_commit, "synthetic-commit"),
  file.exists(file.path(
    root, "postprocess_aggregate", "slider_resampling_test_explained_structure_by_fold.csv"
  )),
  file.exists(file.path(
    root, "postprocess_aggregate", "slider_resampling_test_explained_structure_summary.csv"
  )),
  file.exists(file.path(
    root, "postprocess_images", "slider_resampling_test_explained_structure_by_fold.png"
  ))
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
training_only <- prepare_brain_cv_split(
  full_data, 2L, 1L, 1L, include_omitted_data = FALSE
)
stopifnot(
  is.null(training_only$cross_validation$test_X),
  is.null(training_only$cross_validation$test_labels),
  length(training_only$cross_validation$test_indices) > 0L
)
reference_dir <- file.path(
  root, "results", "brain", "aggregate", "h_stability", "maximum_margin_maps"
)
dir.create(reference_dir, recursive = TRUE)
jsonlite::write_json(
  list(
    schema_version = 2L,
    run_complete = TRUE,
    status = "complete",
    validation_status = "complete_data_production",
    first_H_with_perfect_in_sample_separation = "3"
  ),
  file.path(dirname(reference_dir), "application_run_status.json"),
  auto_unbox = TRUE
)
write.csv(
  data.frame(coefficient = c(1, 0, 0, 0)),
  file.path(reference_dir, "reconstruction_loading_h3.csv"),
  row.names = FALSE
)
reference_raw_dir <- file.path(
  root, "results", "brain", "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS"
)
dir.create(reference_raw_dir, recursive = TRUE)
write.csv(
  rbind(c(0, 0, 0), c(1, 0, 0), c(0, 1, 0), c(0, 0, 1)),
  file.path(reference_raw_dir, "points.csv"),
  row.names = FALSE
)
write.csv(matrix(1:4, nrow = 1L), file.path(reference_raw_dir, "elements.csv"), row.names = FALSE)
evaluation <- result
evaluation$n_comp <- 3L
evaluation$slider_h3 <- c(1, 0, 0, 0)
evaluation$cross_validation$train_indices <- 1:8
evaluation$cross_validation$omitted_indices <- 9:10
evaluation$regularization_boundaries <- data.frame(
  quantity = "functional mean",
  component = 1L,
  selected_lambda = 0.01,
  grid_min = 0.001,
  grid_max = 0.1,
  selected_at_lower_boundary = FALSE,
  selected_at_upper_boundary = FALSE
)
evaluation_2 <- evaluation
evaluation_2$cross_validation$fold_index <- 2L
aggregated <- aggregate_slider_resampling(
  list(evaluation, evaluation_2),
  file.path(root, "aggregate"),
  file.path(root, "images"),
  list(PATH_RESULTS = file.path(root, "results"), PATH_APPLICATION_DATA = "unused")
)
stopifnot(
  aggregated$fits == 2L,
  aggregated$comparable_H3_fits == 2L,
  isTRUE(aggregated$all_test_data_unused),
  isTRUE(all.equal(aggregated$comparisons$mass_correlation, c(1, 1)))
)

fpcr_reference_dir <- file.path(
  root, "results", "brain", "aggregate", "fpcr_h_stability", "maximum_margin_maps"
)
dir.create(fpcr_reference_dir, recursive = TRUE)
jsonlite::write_json(
  list(
    schema_version = 2L,
    run_complete = TRUE,
    status = "complete",
    validation_status = "complete_data_production",
    dimension_reducer = "fPCR",
    first_H_with_perfect_in_sample_separation = "not_evaluated",
    H3_hard_margin_separable = FALSE
  ),
  file.path(dirname(fpcr_reference_dir), "application_run_status.json"),
  auto_unbox = TRUE
)
write.csv(
  data.frame(coefficient = c(1, 0, 0, 0)),
  file.path(fpcr_reference_dir, "reconstruction_loading_h3.csv"),
  row.names = FALSE
)
fpcr_reference_raw_dir <- file.path(
  root, "results", "brain", "fpcr_h_stability", "fpcr_h_stability_H6", "batch_1", "raw", "fPCR"
)
dir.create(fpcr_reference_raw_dir, recursive = TRUE)
file.copy(
  file.path(reference_raw_dir, c("points.csv", "elements.csv")),
  fpcr_reference_raw_dir
)
fpcr_evaluation <- evaluation
fpcr_evaluation$dimension_reducer <- "fPCR"
fpcr_evaluation$h3_hard_margin_separable <- FALSE
fpcr_evaluation_2 <- fpcr_evaluation
fpcr_evaluation_2$cross_validation$fold_index <- 2L
fpcr_aggregated <- aggregate_slider_resampling(
  list(fpcr_evaluation, fpcr_evaluation_2),
  file.path(root, "fpcr_aggregate"),
  file.path(root, "fpcr_images"),
  list(PATH_RESULTS = file.path(root, "results"), PATH_APPLICATION_DATA = "unused")
)
stopifnot(
  identical(fpcr_aggregated$dimension_reducer, "fPCR"),
  identical(fpcr_aggregated$complete_data_reference_target, "fpcr_h_stability"),
  identical(fpcr_aggregated$comparable_H3_fits, 2L),
  !isTRUE(fpcr_aggregated$all_H3_hard_margin_separable)
)
unlink(root, recursive = TRUE)

cat("slider resampling checks passed\n")
