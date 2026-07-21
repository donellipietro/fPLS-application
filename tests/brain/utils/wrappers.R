# = ========================================================================== =
# - Script: wrappers.R
# - Desc: Thin R/process/provenance adapter around the native 3D driver.
# = ========================================================================== =

git_commit <- function(path) {
  output <- system2(
    "git",
    c("-C", shQuote(normalizePath(path)), "rev-parse", "HEAD"),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop(glue::glue("cannot resolve git commit at {path}"))
  trimws(output[1])
}

read_cpp_matrix <- function(file) {
  value <- as.matrix(suppressWarnings(read.csv(file, check.names = FALSE)))
  storage.mode(value) <- "double"
  value
}

check_matrix_shape <- function(value, rows, cols, label) {
  if (!identical(dim(value), c(as.integer(rows), as.integer(cols)))) {
    stop(glue::glue(
      "{label} shape mismatch: got {paste(dim(value), collapse = ' x ')}, ",
      "expected {rows} x {cols}"
    ))
  }
}

run_with_heartbeat <- function(command, log_file, heartbeat_seconds = 60L) {
  heartbeat_seconds <- as.integer(heartbeat_seconds)
  if (is.na(heartbeat_seconds) || heartbeat_seconds < 1L) stop("heartbeat_seconds must be positive")
  log_file <- shQuote(log_file)
  heartbeat_command <- glue::glue(
    "({command} >> {log_file} 2>&1 & native_pid=$!; started=$(date +%s); ",
    "(while kill -0 \"$native_pid\" 2>/dev/null; do sleep {heartbeat_seconds}; ",
    "if kill -0 \"$native_pid\" 2>/dev/null; then now=$(date +%s); ",
    "printf '%s - fPLS fit still running (%ss elapsed)\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" ",
    "\"$((now - started))\" >> {log_file}; fi; done) & heartbeat_pid=$!; ",
    "wait \"$native_pid\"; native_status=$?; kill \"$heartbeat_pid\" 2>/dev/null || true; ",
    "wait \"$heartbeat_pid\" 2>/dev/null || true; exit \"$native_status\")"
  )
  system_with_memory(heartbeat_command, ignore.stdout = IGNORE_CPP_OUTPUT)
}

fit_native_model <- function(data, path_list, test_options) {
  cfg <- load_config()
  raw_dir <- file.path(path_list$batch, "raw", "R1_fPLS")
  input_files <- write_brain_native_inputs(data, raw_dir)
  params_file <- file.path(raw_dir, "params.json")
  telemetry_file <- file.path(raw_dir, "telemetry.json")
  log_file <- file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt"))

  outer_commit <- git_commit(cfg$PATH_FDAPDE_CPP)
  core_commit <- git_commit(file.path(cfg$PATH_FDAPDE_CPP, "fdaPDE", "core"))
  provenance <- c(
    test_options$provenance,
    list(
      suite = test_suite,
      scenario = test_options$name_test,
      model = "R1_fPLS",
      runtime_profile = Sys.getenv("TESTBENCH_PROFILE", unset = "unknown"),
      outer_branch = cfg$FDAPDE_CPP_BRANCH,
      outer_commit = outer_commit,
      core_commit = core_commit,
      data_path = test_options$data$source_path,
      centering = test_options$data$centering
    ),
    if (isTRUE(test_options$cross_validation$enabled)) list(
      cross_validation_split = test_options$cross_validation[c(
        "n_folds", "repeat_index", "fold_index", "seed"
      )]
    ) else list()
  )
  params <- list(
    model = "R1_fPLS",
    n_comp = test_options$model$n_comp,
    center = FALSE,
    calibration = test_options$regularization$calibration,
    fixed_direction_lambda = test_options$regularization$fixed_direction_lambda,
    fixed_loading_lambda = test_options$regularization$fixed_loading_lambda,
    lambda_grid = test_options$regularization$lambda_grid,
    gcv_seed = test_options$regularization$gcv_seed,
    gcv_probes = test_options$regularization$gcv_probes,
    max_iter = test_options$regularization$max_iter,
    tolerance = test_options$regularization$tolerance,
    X_file = input_files$X,
    Y_file = input_files$Y,
    nodes_file = input_files$nodes,
    elements_file = input_files$elements,
    boundary_file = input_files$boundary,
    output_dir = raw_dir,
    write_reconstructions = isTRUE(test_options$output$write_reconstructions),
    write_beta = isTRUE(test_options$output$write_beta),
    provenance = provenance
  )
  write_json(params, params_file, auto_unbox = TRUE, digits = NA, pretty = TRUE)

  binary <- file.path(path_list$cpp_script, "fit_model")
  runner <- file.path(path_list$repo, "cpp", "run.sh")
  command <- glue::glue("{shQuote(runner)} --quiet -- {shQuote(binary)} {shQuote(params_file)}")
  unlink(telemetry_file)
  cat("- Native fPLS process started; heartbeat every 60 seconds\n")
  run_stats <- run_with_heartbeat(command, log_file)
  cat("- Native fPLS process completed\n")
  if (!identical(run_stats$status, 0L) && file.exists(telemetry_file)) {
    warning("resource measurement returned nonzero after the native process wrote completion telemetry")
    run_stats$status <- 0L
  }
  if (!identical(run_stats$status, 0L)) {
    return(list(MODE = "R1_fPLS", status = run_stats$status, raw_output_dir = raw_dir))
  }

  telemetry <- fromJSON(telemetry_file, simplifyVector = TRUE)
  n_comp <- test_options$model$n_comp
  n_units <- nrow(data$X_centered)
  n_nodes <- ncol(data$X_centered)
  n_responses <- ncol(data$Y)
  component_diagnostics <- suppressWarnings(read.csv(
    file.path(raw_dir, "component_diagnostics.csv"),
    check.names = FALSE
  ))

  raw <- list(
    X_space_directions = read_cpp_matrix(file.path(raw_dir, "x_space_directions_coefficients.csv")),
    Y_space_directions = read_cpp_matrix(file.path(raw_dir, "y_space_directions.csv")),
    X_latent_scores = read_cpp_matrix(file.path(raw_dir, "x_latent_scores.csv")),
    Y_latent_scores = read_cpp_matrix(file.path(raw_dir, "y_latent_scores.csv")),
    X_loadings = read_cpp_matrix(file.path(raw_dir, "x_loadings_coefficients.csv")),
    Y_loadings = read_cpp_matrix(file.path(raw_dir, "y_loadings.csv")),
    direction_lambdas = read_cpp_matrix(file.path(raw_dir, "direction_lambdas.csv")),
    loading_lambdas = read_cpp_matrix(file.path(raw_dir, "loading_lambdas.csv")),
    iteration_counts = component_diagnostics$iterations,
    monotone = component_diagnostics$monotone,
    objective = component_diagnostics$objective,
    hit_max_iter = component_diagnostics$hit_max_iter,
    finite_solution = component_diagnostics$finite_solution,
    objective_history = lapply(seq_len(n_comp), function(h) {
      as.numeric(read_cpp_matrix(file.path(raw_dir, glue::glue("objective_history_h{h}.csv"))))
    })
  )
  check_matrix_shape(raw$X_space_directions, n_nodes, n_comp, "X directions")
  check_matrix_shape(raw$Y_space_directions, n_responses, n_comp, "Y directions")
  check_matrix_shape(raw$X_latent_scores, n_units, n_comp, "X scores")
  check_matrix_shape(raw$Y_latent_scores, n_units, n_comp, "Y scores")
  check_matrix_shape(raw$X_loadings, n_nodes, n_comp, "X loadings")
  check_matrix_shape(raw$Y_loadings, n_responses, n_comp, "Y loadings")

  raw$Y_hat <- lapply(seq_len(n_comp), function(h) {
    read_cpp_matrix(file.path(raw_dir, glue::glue("y_hat_h{h}.csv")))
  })
  raw$X_hat_locations <- if (isTRUE(test_options$output$write_reconstructions)) {
    lapply(seq_len(n_comp), function(h) {
      read_cpp_matrix(file.path(raw_dir, glue::glue("x_hat_locations_h{h}.csv")))
    })
  } else NULL
  raw$Beta_coefficients <- if (isTRUE(test_options$output$write_beta)) {
    lapply(seq_len(n_comp), function(h) {
      read_cpp_matrix(file.path(raw_dir, glue::glue("beta_coefficients_h{h}.csv")))
    })
  } else NULL

  if (!isTRUE(test_options$output$retain_native_inputs)) {
    unlink(unlist(input_files, use.names = FALSE))
  }

  list(
    MODE = "R1_fPLS",
    status = 0L,
    results = c(
      raw,
      list(
        telemetry = telemetry,
        provenance = telemetry$provenance,
        raw_output_dir = raw_dir,
        execution_time = telemetry$wall_seconds,
        peak_ram_mib = run_stats$peak_ram_mib,
        setup_seconds = telemetry$setup_seconds,
        fit_seconds = telemetry$fit_seconds,
        output_seconds = telemetry$output_seconds,
        n_basis = telemetry$n_basis,
        calibration = telemetry$calibration
      )
    )
  )
}

fit_model <- function(model_name, domain, data, path_list, test_options) {
  if (!identical(model_name, "R1_fPLS")) {
    stop(glue::glue("The model {model_name} does not exist"))
  }
  fit_native_model(data, path_list, test_options)
}
