# check that prefix errors include every response and scalar separation keeps its previous interpretation
source("tests/brain/utils/models_evaluation.R")

options <- list(
  model = list(n_comp = 2L), resampling = list(enabled = FALSE),
  regularization = list(lambda_grid = c(0.001, 0.1)),
  mean_estimation = list(lambda_grid = c(0.001, 0.1)),
  provenance = list(validation_status = "synthetic_check")
)
Y <- cbind(c(-2, -1, 1, 2), c(3, 1, -1, -3))
model <- list(MODE = "fPCR", status = 0L, results = list(
  Y_hat = list(Y / 2, Y), fpca_lambdas = matrix(c(0.01, 0.01), 2L),
  direction_lambdas = matrix(NaN, 2L), loading_lambdas = matrix(NaN, 2L),
  telemetry = list(mean_selected_lambda = 0.01)
))
data <- list(Y = Y, labels = c("SCHZ", "SCHZ", "CTRL", "CTRL"))
value <- evaluate_results(model, data, options)
# the hand-computed half-response residuals give SSE 2.5 and 5 while the second prefix is exact
stopifnot(isTRUE(all.equal(value$response_errors$sse, c(2.5, 5, 0, 0))))
# MSE divides each response's own SSE by the four training subjects
stopifnot(isTRUE(all.equal(value$response_errors$mse, c(0.625, 1.25, 0, 0))))
# multivariate evaluation explicitly omits scalar classification instead of flattening the predictions
stopifnot(is.null(value$separation), identical(value$classification_status, "not_applicable_multivariate_response"))

data$Y <- Y[, 1L, drop = FALSE]
model$results$Y_hat <- lapply(model$results$Y_hat, function(value) value[, 1L, drop = FALSE])
scalar <- evaluate_results(model, data, options)
# both scalar prefixes order CTRL above SCHZ, giving AUC one and perfect separation
stopifnot(all(scalar$separation$auc == 1), all(scalar$separation$perfect_separation))
# scalar status and two prefix rows preserve the classification consumer's contract
stopifnot(identical(scalar$classification_status, "scalar_response"), nrow(scalar$separation) == 2L)
source("tests/brain/utils/slider_resampling.R")
multi_slider <- list(MODE = "R1_fPLS", status = 0L, results = list(Y_loadings = matrix(1, 2L, 2L)))
error <- tryCatch(evaluate_slider_resampling(multi_slider, list(), options), error = identity)
# the classification slider rejects a multivariate response before projecting or choosing a scalar loading
stopifnot(inherits(error, "error"), grepl("one response column", conditionMessage(error), fixed = TRUE))
cat("Native scalar/multivariate response evaluation checks passed\n")
