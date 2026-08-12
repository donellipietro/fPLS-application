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

historical_lambda_grid <- function() {
  10^seq(-3, -1, by = 0.2)
}

generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  cfg <- load_config()
  is_cv <- name_main_test == "out_of_sample"
  models <- brain_model_catalog(include_fpcr = is_cv)
  fit_native <- is_cv || (name_main_test != "smoke_overall_mean" && !SMOKE_TEST)
  n_comp <- if (is_cv && SMOKE_TEST) 1L else if (name_main_test %in% c("h_stability", "out_of_sample")) 6L else 3L
  n_folds <- if (is_cv) {
    if (SMOKE_TEST) 2L else as.integer(Sys.getenv("FPLS_CV_FOLDS", unset = "5"))
  } else 1L
  n_repeats <- if (is_cv) {
    if (SMOKE_TEST) 1L else as.integer(Sys.getenv("FPLS_CV_REPEATS", unset = "10"))
  } else 1L
  if (is_cv && (n_folds < 2L || n_repeats < 1L)) stop("invalid repeated-CV dimensions")
  canonical_cv <- is_cv && !SMOKE_TEST && n_folds == 5L && n_repeats == 10L

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
      } else if (fit_native) {
        "single_H6_rotated_prefix_stability"
      } else "smoke_prepare_only"
    ),
    model = list(dimension = 3L, n_comp = n_comp, center = FALSE, discretization = "tetrahedral_fem"),
    data = list(
      source_path = cfg$PATH_APPLICATION_DATA,
      centering = "overall_mean",
      response = "CNTRLvsSCHZ_recoded",
      fit_all_subjects = !is_cv
    ),
    regularization = list(
      calibration = if (is_cv && SMOKE_TEST) "fixed" else "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = historical_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      max_iter = if (is_cv && SMOKE_TEST) 1L else 1000L,
      tolerance = 1e-8,
      status = "historical_application_grid_inventory_pending_final_methods_decision"
    ),
    provenance = list(
      schema_version = 1L,
      template_commit = "167e8c2ec240e0f247a1853cbe61e9b7d7e3890a",
      reference_application_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      simulation_reference_commit = "24ac4b95335db22c1d149dcaa627b89d96460819",
      authoritative_centering = "overall_mean",
      historical_group_mean_overwrite = "not_ported_as_active_behavior",
      validation_status = if (is_cv) {
        if (SMOKE_TEST) {
          "cross_validation_smoke"
        } else if (canonical_cv) {
          "cross_validation_production"
        } else {
          "cross_validation_noncanonical"
        }
      } else if (fit_native) "planned_not_production_validated" else "smoke_data_preparation_only",
      template_runtime_commit = "89ba803b85c76b40aab8af2037b779fd29677924"
    )
  )

  if (is_cv) {
    options$cross_validation <- list(
      enabled = TRUE,
      n_folds = n_folds,
      n_repeats = n_repeats,
      seed = 0L,
      repeat_index = 1L,
      fold_index = 1L,
      inner_folds = if (SMOKE_TEST) 2L else 5L,
      evaluation_components = if (SMOKE_TEST) 1L else 3:6,
      svm_cost_grid = if (SMOKE_TEST) c(0.1, 1) else 10^seq(-3, 3),
      class_weighting = "inverse_training_frequency",
      primary_components = min(3L, n_comp)
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
        value$name_test <- glue::glue("out_of_sample_r{sprintf('%02d', repeat_index)}_f{sprintf('%02d', fold_index)}")
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
