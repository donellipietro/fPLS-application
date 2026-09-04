# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the four supported application option queues.
# = ========================================================================== =

brain_model_catalog <- function() {
  list(names = "R1_fPLS", labels = "R1-fPLS", colors = "#2b6cb0")
}

standard_lambda_grid <- function() 10^(-15:2)
fpcr_h20_lambda_grid <- function() 10^(-15:6)

generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  cfg <- load_config()
  is_slider <- identical(name_main_test, "slider_resampling")
  is_fpcr_h20 <- identical(name_main_test, "fpcr_h20_separation")
  models <- if (is_fpcr_h20) {
    list(names = "fPCR", labels = "fPCR", colors = "#2f855a")
  } else brain_model_catalog()
  fit_native <- is_slider || (name_main_test != "smoke_overall_mean" && !SMOKE_TEST)
  n_comp <- if (is_fpcr_h20) 20L else if (is_slider && SMOKE_TEST) 3L else if (
    name_main_test %in% c("h_stability", "slider_resampling")
  ) 6L else 3L
  n_folds <- if (is_slider) {
    if (SMOKE_TEST) 2L else as.integer(Sys.getenv("FPLS_CV_FOLDS", unset = "5"))
  } else 1L
  n_repeats <- if (is_slider) {
    if (SMOKE_TEST) 1L else as.integer(Sys.getenv("FPLS_CV_REPEATS", unset = "10"))
  } else 1L
  if (is_slider && (n_folds < 2L || n_repeats < 1L)) stop("invalid resampling dimensions")
  canonical_slider <- is_slider && !SMOKE_TEST && n_folds == 5L && n_repeats == 10L

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
      run_settings_status = if (is_slider) {
        "repeated_stratified_delete_one_fold_slider_stability"
      } else if (is_fpcr_h20) {
        "single_H20_fpcr_separation_diagnostic"
      } else if (fit_native) "single_H6_slider_prefix_stability" else "smoke_prepare_only"
    ),
    model = list(
      dimension = 3L, n_comp = n_comp, center = FALSE,
      discretization = "tetrahedral_fem"
    ),
    data = list(
      source_path = cfg$PATH_APPLICATION_DATA,
      centering = "overall_gcv_smoothed_functional_mean",
      response = "CNTRLvsSCHZ_recoded",
      fit_all_subjects = !is_slider
    ),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = if (is_fpcr_h20) fpcr_h20_lambda_grid() else standard_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      max_iter = if (is_slider && SMOKE_TEST) 1L else 1000L,
      tolerance = 1e-8,
      fixed_lambda_status = "inactive_unless_calibration_is_fixed",
      status = if (is_fpcr_h20) {
        "exploratory_fpca_upper_grid_extension_after_boundary_selection"
      } else "expanded_application_GCV_grid"
    ),
    mean_estimation = list(
      method = "tetrahedral_P1_FEM_GCV_smoothed_functional_mean",
      lambda_grid = standard_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      scope = if (is_slider) "split_training_subjects_only" else "all_subjects",
      status = "expanded_application_GCV_grid"
    ),
    provenance = list(
      schema_version = 2L,
      template_commit = "167e8c2ec240e0f247a1853cbe61e9b7d7e3890a",
      reference_application_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      simulation_reference_commit = "24ac4b95335db22c1d149dcaa627b89d96460819",
      authoritative_centering = "overall_gcv_smoothed_functional_mean",
      historical_group_mean_overwrite = "not_ported_as_active_behavior",
      validation_status = if (is_slider) {
        if (SMOKE_TEST) "slider_resampling_smoke" else if (canonical_slider) {
          "slider_resampling_production"
        } else "slider_resampling_noncanonical"
      } else if (is_fpcr_h20) {
        "complete_data_exploratory_diagnostic"
      } else if (fit_native) "complete_data_production" else "smoke_data_preparation_only",
      template_runtime_commit = "89ba803b85c76b40aab8af2037b779fd29677924"
    )
  )

  if (is_slider) {
    options$resampling <- list(
      enabled = TRUE,
      purpose = "interpretive_slider_stability",
      n_folds = n_folds,
      n_repeats = n_repeats,
      seed = 0L,
      repeat_index = 1L,
      fold_index = 1L,
      test_usage = "omitted_subjects_define_training_perturbation_only"
    )
    options$output <- list(
      write_reconstructions = FALSE,
      write_beta = FALSE,
      retain_native_inputs = FALSE
    )
    options_list <- unlist(lapply(seq_len(n_repeats), function(repeat_index) {
      lapply(seq_len(n_folds), function(fold_index) {
        value <- options
        value$resampling$repeat_index <- repeat_index
        value$resampling$fold_index <- fold_index
        value$name_test <- glue::glue(
          "slider_resampling_r{sprintf('%02d', repeat_index)}_f{sprintf('%02d', fold_index)}"
        )
        value
      })
    }), recursive = FALSE)
  } else {
    options$name_test <- glue::glue("{name_main_test}_H{n_comp}")
    options$output <- list(
      write_reconstructions = TRUE,
      write_beta = !is_fpcr_h20,
      retain_native_inputs = TRUE
    )
    options_list <- list(options)
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
