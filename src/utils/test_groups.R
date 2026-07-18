# = ========================================================================== =
# - Script: test_groups.R
# - Desc: Helpers for grouped tests and per-test threading metadata.
# = ========================================================================== =


#' Source a test-suite configuration file into an isolated environment.
#'
#' @param test_suite Test-suite directory name.
#' @return The value produced by `load_test_suite_config_env`.
load_test_suite_config_env <- function(test_suite) {
  config_file <- file.path("tests", test_suite, "config.R")
  env <- new.env(parent = globalenv())
  if (file.exists(config_file)) {
    source(config_file, local = env)
  }
  env
}


if (!exists("%||%", mode = "function")) {
  #' Describe the `%||%` helper used by this repository.
  #'
  #' @param x Input object.
  #' @param y Fallback or comparison value.
  #' @return The value produced by `%||%`.
  `%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0) y else x
  }
}


#' Expand requested test names through suite-level test groups.
#'
#' @param test_suite Test-suite directory name.
#' @param name_main_test Main test name or test-group name.
#' @return The value produced by `resolve_test_names`.
resolve_test_names <- function(test_suite, name_main_test) {
  env <- load_test_suite_config_env(test_suite)
  test_groups <- if (exists("test_groups", envir = env, inherits = FALSE)) {
    get("test_groups", envir = env)
  } else {
    list()
  }

  resolved <- unlist(lapply(name_main_test, function(test_name) {
    group <- test_groups[[test_name]]
    if (is.null(group)) test_name else group
  }), use.names = FALSE)

  unique(as.character(resolved))
}


#' Resolve the threading mode declared by a test option.
#'
#' @param test_options Nested option object loaded from JSON.
#' @param default Fallback value used when the option is missing.
#' @return The value produced by `test_threading_mode`.
test_threading_mode <- function(test_options, default = "single") {
  mode <- NULL
  if (!is.null(test_options$test_options)) {
    mode <- test_options$test_options$threading
  }
  mode <- mode %||% default
  mode <- tolower(as.character(mode[1]))
  if (!mode %in% c("single", "multi")) {
    stop("test_options$threading must be either 'single' or 'multi'.", call. = FALSE)
  }
  mode
}


#' Read all option JSONs in a queue and return their common threading mode.
#'
#' @param path_queue Directory where option JSON files are stored.
#' @param default Fallback value used when the option is missing.
#' @return The value produced by `queue_threading_mode`.
queue_threading_mode <- function(path_queue, default = "single") {
  option_files <- sort(list.files(path_queue, pattern = "\\.json$", full.names = TRUE))
  if (length(option_files) == 0) return(default)

  modes <- vapply(option_files, function(file_options) {
    test_options <- jsonlite::fromJSON(file_options)
    test_threading_mode(test_options, default = default)
  }, character(1))

  modes <- unique(modes)
  if (length(modes) != 1) {
    stop(
      glue::glue(
        "Queue contains mixed threading modes: ",
        "{glue::glue_collapse(modes, sep = ', ')}. ",
        "Split these options into separate tests."
      ),
      call. = FALSE
    )
  }

  modes
}
