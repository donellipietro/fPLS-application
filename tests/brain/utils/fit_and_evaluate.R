# = ========================================================================== =
# - Script: fit_and_evaluate.R
# - Desc: Fits and evaluates the native application model for one option.
# = ========================================================================== =

native_model_matches_options <- function(model, model_name, test_options, data, path_list) {
  if (!identical(model$MODE, model_name) || is.null(model$results$telemetry)) return(FALSE)
  telemetry <- model$results$telemetry
  same <- function(left, right) isTRUE(all.equal(left, right))
  fit_configuration <- telemetry$provenance$fit_configuration
  mean_configuration <- telemetry$provenance$mean_estimation_configuration
  configured <- function(name) {
    value <- telemetry[[name]]
    if (is.null(value)) fit_configuration[[name]] else value
  }
  same_md5 <- function(left, right) {
    left <- unlist(left, use.names = TRUE)
    right <- unlist(right, use.names = TRUE)
    same(left[sort(names(left))], right[sort(names(right))])
  }
  split_matches <- if (isTRUE(test_options$resampling$enabled)) {
    observed <- telemetry$provenance$resampling_split
    expected <- test_options$resampling[c(
      "n_folds", "n_repeats", "repeat_index", "fold_index", "seed",
      "purpose", "test_usage"
    )]
    same(
      observed[sort(names(observed))],
      expected[sort(names(expected))]
    )
  } else TRUE
  cfg <- load_config()
  binary <- file.path(path_list$cpp_script, "fit_model")
  binary_md5 <- if (file.exists(binary)) unname(as.character(tools::md5sum(binary))) else NA_character_
  fixed_lambda_matches <- if (identical(model_name, "fPCR")) {
    same(configured("fixed_fpca_lambda"), test_options$regularization$fixed_loading_lambda)
  } else {
    same(configured("fixed_direction_lambda"), test_options$regularization$fixed_direction_lambda) &&
      same(configured("fixed_loading_lambda"), test_options$regularization$fixed_loading_lambda)
  }
  fpca_implementation_matches <- if (identical(model_name, "fPCR")) {
    identical(telemetry$fpca_implementation, "public_fdaPDE_fPCR_with_explicit_edf_control") &&
      identical(telemetry$fpca_gcv_edf$probe_count_source, "gcv_probes") &&
      identical(telemetry$fpca_gcv_edf$seed_source, "gcv_seed") &&
      identical(telemetry$fpca_gcv_edf$seed_mode, "explicit_deterministic")
  } else TRUE
  same(telemetry$schema_version, 4L) &&
    identical(telemetry$model, model_name) &&
    same(telemetry$n_components, test_options$model$n_comp) &&
    same(configured("calibration"), test_options$regularization$calibration) &&
    fpca_implementation_matches &&
    fixed_lambda_matches &&
    same(as.numeric(configured("lambda_grid")), test_options$regularization$lambda_grid) &&
    same(configured("gcv_seed"), test_options$regularization$gcv_seed) &&
    same(configured("gcv_probes"), test_options$regularization$gcv_probes) &&
    identical(telemetry$centering, "training_overall_gcv_smoothed_functional_mean") &&
    same(as.numeric(telemetry$mean_lambda_grid), test_options$mean_estimation$lambda_grid) &&
    same(telemetry$mean_gcv_seed, test_options$mean_estimation$gcv_seed) &&
    same(telemetry$mean_gcv_probes, test_options$mean_estimation$gcv_probes) &&
    same(as.numeric(mean_configuration$lambda_grid), test_options$mean_estimation$lambda_grid) &&
    same(mean_configuration$gcv_seed, test_options$mean_estimation$gcv_seed) &&
    same(mean_configuration$gcv_probes, test_options$mean_estimation$gcv_probes) &&
    same(configured("max_iter"), test_options$regularization$max_iter) &&
    same(configured("tolerance"), test_options$regularization$tolerance) &&
    same(telemetry$write_reconstructions, isTRUE(test_options$output$write_reconstructions)) &&
    same(telemetry$write_beta, isTRUE(test_options$output$write_beta)) &&
    identical(telemetry$provenance$centering, data$centering) &&
    identical(telemetry$provenance$application_commit, git_commit(path_list$repo)) &&
    identical(telemetry$provenance$application_worktree_clean, git_is_clean(path_list$repo)) &&
    identical(telemetry$provenance$outer_commit, git_commit(cfg$PATH_FDAPDE_CPP)) &&
    identical(telemetry$provenance$core_commit, git_commit(file.path(cfg$PATH_FDAPDE_CPP, "fdaPDE", "core"))) &&
    identical(telemetry$provenance$native_binary_md5, binary_md5) &&
    same_md5(telemetry$provenance$input_md5, data$input_md5) &&
    identical(telemetry$provenance$preprocessing_md5, data$preprocessing_md5) &&
    split_matches
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
        reuse_model <- native_model_matches_options(model, model_name, test_options, data, path_list)
      }
      if (reuse_model) cat(glue::glue("- Reusing cached model: {model_name}\n", .trim = FALSE))
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
