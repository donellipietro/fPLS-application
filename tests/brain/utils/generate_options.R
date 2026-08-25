# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates minimal application options without starting production runs.
# = ========================================================================== =

brain_model_catalog <- function(include_fpcr = FALSE) {
  list(
    names = c("R1_fPLS", if (include_fpcr) "fPCR"),
    labels = c("R1-fPLS", if (include_fpcr) "fPCR"),
    colors = c("#2b6cb0", if (include_fpcr) "#2f855a")
  )
}

standard_lambda_grid <- function() {
  10^(-15:2)
}

generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  cfg <- load_config()
  is_cv <- name_main_test == "out_of_sample"
  is_slider_resampling <- name_main_test == "slider_resampling"
  uses_splits <- is_cv || is_slider_resampling
  models <- brain_model_catalog(include_fpcr = is_cv)
  fit_native <- uses_splits || (name_main_test != "smoke_overall_mean" && !SMOKE_TEST)
  n_comp <- if (is_cv && SMOKE_TEST) 1L else if (is_slider_resampling && SMOKE_TEST) 3L else if (name_main_test %in% c(
    "h_stability", "slider_resampling", "out_of_sample"
  )) 6L else 3L
  n_folds <- if (uses_splits) {
    if (SMOKE_TEST) 2L else as.integer(Sys.getenv("FPLS_CV_FOLDS", unset = "5"))
  } else 1L
  n_repeats <- if (uses_splits) {
    if (SMOKE_TEST) 1L else as.integer(Sys.getenv("FPLS_CV_REPEATS", unset = "10"))
  } else 1L
  if (uses_splits && (n_folds < 2L || n_repeats < 1L)) stop("invalid repeated split dimensions")
  canonical_cv <- is_cv && !SMOKE_TEST && n_folds == 5L && n_repeats == 10L
  canonical_slider_resampling <- is_slider_resampling && !SMOKE_TEST && n_folds == 5L && n_repeats == 10L

  options <- list(
    model_names = models$names,
    model_labels = models$labels,
    model_colors = models$colors,
    cpp_script = test_suite,
    test_options = list(
      n_reps = 1L,
      varying_options = "none",
      threading = "single",
      smoke_test = SMOKE_TEST,
      fit_native = fit_native,
      run_settings_status = if (is_cv) {
        "repeated_stratified_outer_CV"
      } else if (is_slider_resampling) {
        "repeated_stratified_delete_one_fold_slider_stability"
      } else if (fit_native) {
        "single_H6_slider_prefix_stability"
      } else "smoke_prepare_only"
    ),
    model = list(dimension = 3L, n_comp = n_comp, center = FALSE, discretization = "tetrahedral_fem"),
    data = list(
      source_path = cfg$PATH_APPLICATION_DATA,
      centering = "overall_gcv_smoothed_functional_mean",
      response = "CNTRLvsSCHZ_recoded",
      fit_all_subjects = !uses_splits
    ),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = standard_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      max_iter = if (uses_splits && SMOKE_TEST) 1L else 1000L,
      tolerance = 1e-8,
      fixed_lambda_status = "inactive_unless_calibration_is_fixed",
      status = "application_expanded_GCV_grid_after_H6_loading2_hit_1e-12"
    ),
    mean_estimation = list(
      method = "tetrahedral_P1_FEM_GCV_smoothed_functional_mean",
      lambda_grid = standard_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      scope = if (uses_splits) "split_training_subjects_only" else "all_subjects",
      status = "application_expanded_GCV_grid_including_historical_1e-2"
    ),
    provenance = list(
      schema_version = 2L,
      template_commit = "167e8c2ec240e0f247a1853cbe61e9b7d7e3890a",
      reference_application_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      simulation_reference_commit = "24ac4b95335db22c1d149dcaa627b89d96460819",
      authoritative_centering = "overall_gcv_smoothed_functional_mean",
      historical_group_mean_overwrite = "not_ported_as_active_behavior",
      validation_status = if (is_cv) {
        if (SMOKE_TEST) {
          "cross_validation_smoke"
        } else if (canonical_cv) {
          "cross_validation_production"
        } else {
          "cross_validation_noncanonical"
        }
      } else if (is_slider_resampling) {
        if (SMOKE_TEST) {
          "slider_resampling_smoke"
        } else if (canonical_slider_resampling) {
          "slider_resampling_production"
        } else {
          "slider_resampling_noncanonical"
        }
      } else if (fit_native) "complete_data_production" else "smoke_data_preparation_only",
      template_runtime_commit = "89ba803b85c76b40aab8af2037b779fd29677924"
    )
  )

  if (uses_splits) {
    options$cross_validation <- list(
      enabled = TRUE,
      purpose = if (is_slider_resampling) "interpretive_slider_stability" else "predictive_validation",
      n_folds = n_folds,
      n_repeats = n_repeats,
      seed = 0L,
      repeat_index = 1L,
      fold_index = 1L,
      inner_folds = if (is_slider_resampling) 0L else if (SMOKE_TEST) 2L else 5L,
      evaluation_components = if (is_slider_resampling) seq_len(n_comp) else if (SMOKE_TEST) 1L else 3:6,
      svm_cost_grid = if (is_slider_resampling) 1e6 else if (SMOKE_TEST) c(0.1, 1) else 10^seq(-3, 3),
      class_weighting = if (is_slider_resampling) "none" else "inverse_training_frequency",
      primary_components = min(3L, n_comp),
      fixed_slider_cost = 1e6,
      test_usage = if (is_slider_resampling) "omitted_subjects_define_training_perturbation_only" else "held_out_prediction"
    )
    options$output <- list(
      write_reconstructions = FALSE,
      write_beta = FALSE,
      retain_native_inputs = FALSE
    )
    options_list <- unlist(lapply(seq_len(n_repeats), function(repeat_index) {
      lapply(seq_len(n_folds), function(fold_index) {
        value <- options
        value$cross_validation$repeat_index <- repeat_index
        value$cross_validation$fold_index <- fold_index
        prefix <- if (is_slider_resampling) "slider_resampling" else "out_of_sample"
        value$name_test <- glue::glue("{prefix}_r{sprintf('%02d', repeat_index)}_f{sprintf('%02d', fold_index)}")
        value
      })
    }), recursive = FALSE)
  } else {
    options$name_test <- glue::glue("{name_main_test}_H{n_comp}")
    options$output <- list(
      write_reconstructions = TRUE,
      write_beta = TRUE,
      retain_native_inputs = TRUE
    )
    options_list <- list(options)
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
