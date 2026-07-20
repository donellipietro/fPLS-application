# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates minimal application options without starting production runs.
# = ========================================================================== =

brain_model_catalog <- function() {
  list(
    names = c("R1_fPLS"),
    labels = c("R1-fPLS"),
    colors = c("#2b6cb0")
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

  models <- brain_model_catalog()
  cfg <- load_config()
  fit_native <- name_main_test != "smoke_overall_mean" && !SMOKE_TEST
  n_comp <- if (name_main_test == "h_stability") 6L else 3L

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
      run_settings_status = if (fit_native) "single_H6_prefix_diagnostics_confirmed" else "smoke_prepare_only"
    ),
    model = list(dimension = 3L, n_comp = n_comp, center = FALSE, discretization = "tetrahedral_fem"),
    data = list(
      source_path = cfg$PATH_APPLICATION_DATA,
      centering = "overall_mean",
      response = "CNTRLvsSCHZ_recoded",
      fit_all_subjects = TRUE
    ),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = historical_lambda_grid(),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      max_iter = 1000L,
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
      validation_status = if (fit_native) "planned_not_production_validated" else "smoke_data_preparation_only"
    )
  )

  options$name_test <- glue::glue("{name_main_test}_H{n_comp}")
  options_list <- list(options)
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
