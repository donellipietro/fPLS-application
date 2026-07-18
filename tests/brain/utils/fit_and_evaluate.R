# = ========================================================================== =
# - Script: fit_and_evaluate.R
# - Desc: Fits and evaluates the native application model for one option.
# = ========================================================================== =

native_model_matches_options <- function(model, model_name, test_options) {
  if (!identical(model_name, "R1_fPLS") || is.null(model$results$telemetry)) return(FALSE)
  telemetry <- model$results$telemetry
  same <- function(left, right) isTRUE(all.equal(left, right))
  same(telemetry$schema_version, 1L) &&
    identical(telemetry$model, model_name) &&
    same(telemetry$n_components, test_options$model$n_comp) &&
    same(telemetry$max_iter, test_options$regularization$max_iter) &&
    same(telemetry$tolerance, test_options$regularization$tolerance) &&
    same(as.numeric(telemetry$lambda_grid), test_options$regularization$lambda_grid)
}

fit_and_evaluate_models <- function(path_list, data, domain, batch_index, test_options) {
  results_evaluation <- list()
  evaluation_file <- file.path(
    path_list$batch,
    glue::glue("batch_{batch_index}_results_evaluation.RData")
  )

  for (model_name in test_options$model_names) {
    model_file <- file.path(
      path_list$batch,
      glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")
    )
    object_name <- glue::glue("model_{model_name}")

    if (isTRUE(test_options$test_options$fit_native)) {
      reuse_model <- FALSE
      if (file.exists(model_file) && !FORCE_FIT) {
        load(model_file)
        model <- get(object_name)
        reuse_model <- native_model_matches_options(model, model_name, test_options)
      }
      if (!reuse_model) {
        cat(glue::glue("- Fitting model: {model_name}\n", .trim = FALSE))
        model <- fit_model(model_name, domain, data, path_list, test_options)
        assign(object_name, model)
        save(list = object_name, file = model_file)
        rm(list = object_name)
      }
      results_evaluation[[model_name]] <- evaluate_results(model, data, test_options)
    } else {
      cat("- Native fit skipped by smoke option\n")
      results_evaluation[[model_name]] <- list(
        failed = FALSE,
        status = NA_integer_,
        n_comp = test_options$model$n_comp,
        validation_status = "smoke_data_preparation_only"
      )
    }
  }

  save(index_batch = batch_index, results_evaluation, file = evaluation_file)
  cat(glue::glue("- Batch {batch_index} completed.\n", .trim = FALSE))
}
