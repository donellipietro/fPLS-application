#' Create one or more directories if they do not already exist.
#'
#' @param paths Character vector of paths.
#' @return The value produced by `mkdir`.
mkdir <- function(paths) {
  for (path in paths) {
    if (!file.exists(path)) {
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
    }
  }
}
#' Load the root configuration and return the selected profile.
#'
#' @return The value produced by `load_config`.
load_config <- function() {
  if (!exists("get_config", mode = "function")) {
    source("config.R")
  }

  get_config()
}
#' Join path components and preserve the trailing slash expected by older scripts.
#'
#' @param ... Named options or values passed through to the helper.
#' @return The value produced by `config_path`.
config_path <- function(...) {
  path <- file.path(...)
  needs_slash <- !grepl("[/\\\\]$", path)
  path[needs_slash] <- glue::glue("{path[needs_slash]}{.Platform$file.sep}")
  path
}
#' Create and return the standard path list for a test suite.
#'
#' @param test_suite Test-suite directory name.
#' @return The value produced by `create_paths`.
create_paths <- function(test_suite) {
  cfg <- load_config()

  ## Directories for results
  mkdir(c(cfg$PATH_RESULTS, cfg$PATH_IMAGES, cfg$PATH_TEST_DATA))
  path_results <- config_path(cfg$PATH_RESULTS, test_suite)
  path_images <- config_path(cfg$PATH_IMAGES, test_suite)
  path_data <- config_path(cfg$PATH_TEST_DATA, test_suite)
  mkdir(c(path_results, path_images, path_data))

  ## Temporary directories
  mkdir(c(
    cfg$PATH_TMP,
    cfg$PATH_QUEUE,
    cfg$PATH_LOGS,
    cfg$PATH_TMP_DATA,
    cfg$PATH_TMP_RESULTS,
    cfg$PATH_BUILD
  ))
  path_queue <- config_path(cfg$PATH_QUEUE, test_suite)
  path_logs <- config_path(cfg$PATH_LOGS, test_suite)
  path_tmp_data <- config_path(cfg$PATH_TMP_DATA, test_suite)
  path_tmp_results <- config_path(cfg$PATH_TMP_RESULTS, test_suite)
  mkdir(c(path_queue, path_logs, path_tmp_data, path_tmp_results))

  ## Save all paths needed by the methods in a list
  path_list <- list(
    repo = config_path(cfg$PATH_REPO),
    cpp = config_path(cfg$PATH_CPP),
    build = config_path(cfg$PATH_BUILD),
    results = path_results,
    images = path_images,
    data = path_data,
    queue = path_queue,
    logs = path_logs,
    tmp_data = path_tmp_data,
    tmp_results = path_tmp_results
  )

  return(path_list)
}
#' Extend a path list with directories for one concrete test option.
#'
#' @param path_list Named list of repository, output, queue, and temporary paths.
#' @param name_main_test Main test name or test-group name.
#' @param test_options Nested option object loaded from JSON.
#' @return The value produced by `update_paths`.
update_paths <- function(path_list, name_main_test, test_options) {
  name_test <- test_options$name_test
  if (is.null(name_test) || length(name_test) == 0 || !nzchar(name_test[1])) {
    name_test <- name_main_test
  }

  for (ext in c("images", "data")) {
    path <- path_list[[ext]]
    path <- config_path(path, name_main_test)
    mkdir(path)
    path_list[[ext]] <- path
  }

  for (ext in c("results", "tmp_data", "tmp_results")) {
    path <- path_list[[ext]]
    path <- config_path(path, name_main_test)
    mkdir(path)
    path <- config_path(path, name_test)
    mkdir(path)
    path_list[[ext]] <- path
  }

  ## Add cpp_scripts path to path_list
  path_list$cpp_script_source <- config_path(path_list$cpp, test_options$cpp_script)
  path_list$cpp_script <- config_path(path_list$build, test_options$cpp_script)

  ## Check if the C++ has been compiled
  compiled_files <- list.files(
    path = path_list$cpp_script,
    pattern = "^fit_model",   # regex: starts with "fit_model"
    full.names = TRUE
  )
  if (length(compiled_files) == 0) {
    stop(
      glue::glue(
        "The C++ model has not been compiled!\n",
        "Run: make compile MODEL={test_options$cpp_script}"
      )
    )
  }

  return(path_list)
}
#' Return the directory of the currently running or sourced R script.
#'
#' @return The value produced by `get_script_path`.
get_script_path <- function() {
  # Try Rscript
  args <- commandArgs(trailingOnly = FALSE)
  path <- sub("--file=", "", args[grep("--file=", args)])
  if (length(path) > 0) {
    return(config_path(dirname(normalizePath(path))))
  }

  # Try source()
  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(config_path(dirname(normalizePath(sys.frames()[[1]]$ofile))))
  }

  # Try RStudio
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
    rstudioapi::isAvailable()) {
    return(config_path(dirname(normalizePath(rstudioapi::getSourceEditorContext()$path))))
  }

  # Fallback
  return(NULL)
}
#' Open a file or directory with the operating system default application.
#'
#' @param path File or directory path.
#' @return The value produced by `open`.
open <- function(path) {
  if (.Platform$OS.type == "windows") {
    return(shell.exec(path))
  } else {
    return(invisible(system2("open", path)))
  }
}
