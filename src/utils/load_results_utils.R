# = ========================================================================== =
# - Script: load_results_utils.R
# - Desc: Utilities for reading and aggregating quantitative evaluation results.
#         Includes helpers for time formatting, result extraction, and merging
#         batch outputs into unified data structures for analysis.
# = ========================================================================== =


## Function: format_time
# - Args:
#   * t: a time object returned by Sys.time() differences (with units attribute)
# - Desc:
#   Converts a time duration into seconds, regardless of the original unit.
format_time <- function(t) {
  if (attr(t, "units") == "mins") {
    return(as.numeric(t) * 60)
  } else if (attr(t, "units") == "hours") {
    return(as.numeric(t) * 60 * 60)
  } else {
    return(as.numeric(t))
  }
}


## Function: parse_peak_rss_mib
# - Args:
#   * lines: output produced by /usr/bin/time
#   * sysname: OS name, defaults to the current system
# - Desc:
#   Extracts peak resident memory and normalizes it to MiB.
parse_peak_rss_mib <- function(lines, sysname = Sys.info()[["sysname"]]) {
  line <- grep("maximum resident set size|Maximum resident set size", lines, value = TRUE)
  if (length(line) == 0) return(NaN)

  value <- suppressWarnings(as.numeric(regmatches(line[1], regexpr("[0-9]+(\\.[0-9]+)?", line[1]))))
  if (is.na(value)) return(NaN)

  if (identical(sysname, "Darwin")) value / 1024^2 else value / 1024
}

# legacy alias retained for existing suites
parse_peak_rss_mb <- parse_peak_rss_mib


## Function: r_peak_memory_mb
# - Desc:
#   Reads base R's peak heap usage after gc(reset = TRUE).
r_peak_memory_mb <- function() {
  stats <- gc()
  mb_col <- match("max used", colnames(stats)) + 1
  sum(stats[, mb_col], na.rm = TRUE)
}


## Function: system_with_memory
# - Args:
#   * command: shell command to execute
#   * ignore.stdout: passed through to system2
# - Desc:
#   Runs an external command and returns elapsed time, status, and peak RSS in MiB.
#   Docker profiles request /usr/bin/time inside the container so the measured
#   process is the fitted C++ model rather than the Docker client.
system_with_memory <- function(command, ignore.stdout = FALSE) {
  start.time <- Sys.time()

  if (nzchar(Sys.getenv("DOCKER_IMAGE", unset = ""))) {
    path_tmp <- Sys.getenv("PATH_TMP", unset = tempdir())
    time_file <- tempfile("time_", tmpdir = path_tmp)
    on.exit(unlink(time_file), add = TRUE)

    command <- paste(
      glue::glue("TESTBENCH_MEMORY_FILE={shQuote(time_file)}"),
      command
    )
    status <- system(command, ignore.stdout = ignore.stdout)
    peak_ram_mib <- if (file.exists(time_file)) {
      parse_peak_rss_mib(readLines(time_file, warn = FALSE), sysname = "Linux")
    } else {
      NaN
    }
    return(list(
      execution_time = Sys.time() - start.time,
      peak_ram_mib = peak_ram_mib,
      memory_usage = peak_ram_mib,
      status = status
    ))
  }

  time_bin <- "/usr/bin/time"
  if (!file.exists(time_bin)) {
    status <- system(command, ignore.stdout = ignore.stdout)
    return(list(
      execution_time = Sys.time() - start.time,
      peak_ram_mib = NaN,
      memory_usage = NaN,
      status = status
    ))
  }

  time_file <- tempfile()
  on.exit(unlink(time_file), add = TRUE)

  time_arg <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
  status <- system2(
    time_bin,
    c(time_arg, "-o", shQuote(time_file), "sh", "-c", shQuote(command)),
    stdout = if (ignore.stdout) FALSE else "",
    stderr = ""
  )

  peak_ram_mib <- parse_peak_rss_mib(readLines(time_file, warn = FALSE))
  list(
    execution_time = Sys.time() - start.time,
    peak_ram_mib = peak_ram_mib,
    memory_usage = peak_ram_mib,
    status = status
  )
}


## Function: add_results
# - Args:
#   * data: a data.frame where rows are groups and columns are models
#   * new: a list of vectors containing results for each model
#   * groups_names: optional vector of group labels
# - Desc:
#   Appends a new set of model results to the existing data frame. Automatically
#   adjusts dimensions and names, preserving the original column structure.
add_results <- function(data, new, groups_names = NULL) {

  ## Get column names from data
  names_columns <- colnames(data)

  ## Compute the maximum length among new entries
  n <- 0
  for (i in 1:length(new)) {
    n <- max(c(n, length(new[[i]])))
  }

  ## Initialize the new data data.frame
  if (is.null(groups_names)) {
    new_data <- data.frame(Group = as.character(seq_len(n)))
  } else {
    new_data <- data.frame(Group = groups_names)
  }

  ## Add columns
  for (subgroup in names_columns[-1]) {
    new_data <- cbind(new_data, new[[subgroup]])
  }

  ## Rename columns
  colnames(new_data) <- names_columns

  ## Append to the existing data
  data <- as.data.frame(rbind(data, new_data))
  colnames(data) <- names_columns

  return(data)
}


## Function: extract_new_results
# - Args:
#   * results_evaluation: nested list containing results per model
#   * names_models: character vector with model identifiers
#   * name_result: character or vector specifying which result(s) to extract
# - Desc:
#   Extracts specific evaluation metrics from each model’s result structure.
#   Handles nested lists, converts time units to seconds, and replaces NULLs
#   with NaN values for consistency.
extract_new_results <- function(results_evaluation, names_models, name_result) {

  ## Room for new results
  new_results <- list()
  for (name_model in names_models) {
    ## Router for reading the data
    if (length(name_result) == 1) {
      new_results[[name_model]] <- results_evaluation[[name_model]][[name_result]]
    } else if (length(name_result) == 2) {
      new_results[[name_model]] <- results_evaluation[[name_model]][[name_result[1]]][[name_result[2]]]
    } else {
      stop()
    }
    ## Convert time units if necessary
    if (length(new_results[[name_model]]) == 1 &&
        "units" %in% names(attributes(new_results[[name_model]]))) {
      new_results[[name_model]] <- format_time(new_results[[name_model]])
    }
    ## Replace NULL with NaN
    if (is.null(new_results[[name_model]])) {
      new_results[[name_model]] <- c(NaN)
    }
  }
  return(new_results)
}


## Function: load_quantitative_results
# - Args:
#   * test_options: list containing test and model configuration
#   * path_list: list with paths where batch results are stored
# - Desc:
#   Iteratively loads quantitative results from multiple batches,
#   aggregates them into structured data.frames, and returns a list
#   ready for analysis and visualization.
load_quantitative_results <- function(test_options, path_list) {
  cat(glue::glue(
    "\nLoading quantitative results for {test_options$name_test} ...\n",
    .trim = FALSE
  ))

  ## Get model names, labels, and colors
  model_names  <- test_options$model_names
  model_labels <- test_options$model_labels
  model_colors <- test_options$model_colors

  ## Initialize an empty data.frame template
  names_columns <- c("Group", model_names)
  empty_df <- data.frame(matrix(NaN, nrow = 0, ncol = length(names_columns)))
  colnames(empty_df) <- names_columns

  ## Load the first batch defensively
  batch_index <- 1
  ok <- tryCatch({
    path_batch <- file.path(path_list$results, glue::glue("batch_{batch_index}"))
    load(file.path(path_batch, glue::glue("batch_{batch_index}_results_evaluation.RData")))
    TRUE
  }, error = function(e) {
    cat(glue::glue(
      "Error in test {test_options$name_test} - batch {batch_index}: ",
      "{conditionMessage(e)}\n",
      .trim = FALSE
    ))
    FALSE
  })
  if (!ok) next

  ## Create containers for each entry in results_evaluation
  res <- list()
  for (entry in names(results_evaluation[[1]])) {
    if (!is.list(results_evaluation[[1]][[entry]])) {
      res[[entry]] <- empty_df
    } else {
      res[[entry]] <- list()
      for (sub_entry in names(results_evaluation[[1]][[entry]])) {
        res[[entry]][[sub_entry]] <- empty_df
      }
    }
  }

  ## Load all batches sequentially
  n_reps <- test_options$test_options$n_reps
  for (batch_index in seq_len(n_reps)) {

    ## Safely load batch file
    ok <- tryCatch({
      path_batch <- file.path(path_list$results, glue::glue("batch_{batch_index}"))
      load(file.path(path_batch, glue::glue("batch_{batch_index}_results_evaluation.RData")))
      TRUE
    }, error = function(e) {
      cat(glue::glue(
        "Error in test {test_options$name_test} - batch {batch_index}: ",
        "{conditionMessage(e)}\n",
        .trim = FALSE
      ))
      FALSE
    })
    if (!ok) next

    ## Check that results_evaluation exists
    if (!exists("results_evaluation", inherits = FALSE)) {
      cat(glue::glue(
        "Warning: no `results_evaluation` found in batch {batch_index} file; skipping.\n",
        .trim = FALSE
      ))
      next
    }

    ## Append results for each entry and sub-entry
    for (entry in names(res)) {
      if (is.data.frame(res[[entry]])) {
        res[[entry]] <- add_results(
          res[[entry]],
          extract_new_results(results_evaluation, model_names, entry)
        )
      } else {
        for (sub_entry in names(res[[entry]])) {
          res[[entry]][[sub_entry]] <- add_results(
            res[[entry]][[sub_entry]],
            extract_new_results(results_evaluation, model_names, c(entry, sub_entry))
          )
        }
      }
    }

    cat(glue::glue("- Batch {batch_index} loaded\n", .trim = FALSE))
  }

  cat("\n")

  ## Attach metadata
  res$model_names  <- model_names
  res$model_labels <- model_labels
  res$model_colors <- model_colors
  res$varying_options <- test_options$test_options$varying_options

  return(res)
}


## Function: resolve_option_value
# - Args:
#   * opt_name: character, option name (supports dotted paths like "dimensions.n_nodes")
#   * test_options: list, the full options object to search
# - Desc:
#   Safely resolves the value of a varying option from test_options. Tries a dotted
#   path traversal first; then common containers (top-level, dimensions, noise).
#   Returns the value if found, otherwise NA.
resolve_option_value <- function(opt_name, test_options) {
  if (grepl("\\.", opt_name)) {
    parts <- strsplit(opt_name, "\\.")[[1]]
    v <- test_options
    for (p in parts) {
      if (!is.list(v) || is.null(v[[p]])) return(NA)
      v <- v[[p]]
    }
    return(v)
  }
  if (!is.null(test_options[[opt_name]])) return(test_options[[opt_name]])
  if (!is.null(test_options$dimensions) && !is.null(test_options$dimensions[[opt_name]])) {
    return(test_options$dimensions[[opt_name]])
  }
  if (!is.null(test_options$noise) && !is.null(test_options$noise[[opt_name]])) {
    return(test_options$noise[[opt_name]])
  }
  return(NA)
}


## Function: inject_varying_columns
# - Args:
#   * df: data.frame to augment (may be empty)
#   * varying_vals: named list of {option_name -> scalar value} to inject as columns
# - Desc:
#   Adds one column per varying option into df, recycling values to nrow(df).
#   If a "Group" column exists, new columns are inserted after it; otherwise they
#   are appended. On empty data.frames, only the schema is updated.
inject_varying_columns <- function(df, varying_vals) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    ## Still add columns so the schema is correct
    for (vn in names(varying_vals)) {
      if (is.null(df[[vn]])) df[[vn]] <- numeric(0)
    }
    ## Try to place after Group when columns exist later
    return(df)
  }
  insert_after <- match("Group", colnames(df))
  for (vn in names(varying_vals)) {
    val <- varying_vals[[vn]]
    col_vec <- rep(val, nrow(df))
    if (vn %in% colnames(df)) next
    if (!is.na(insert_after)) {
      ## Insert after "Group"
      left_cols  <- colnames(df)[seq_len(insert_after)]
      right_cols <- colnames(df)[-seq_len(insert_after)]
      df <- cbind(
        df[left_cols],
        setNames(list(col_vec), vn),
        df[right_cols],
        stringsAsFactors = FALSE
      )
    } else {
      df[[vn]] <- col_vec
    }
  }
  df
}


## Function: add_varying_to_all_dfs
# - Args:
#   * x: object to process (data.frame or nested list containing data.frames)
#   * varying_vals: named list of columns to inject (see inject_varying_columns)
# - Desc:
#   Recursively traverses lists and applies column injection to every data.frame
#   contained within, returning an object with the same structure.
add_varying_to_all_dfs <- function(x, varying_vals) {
  if (is.data.frame(x)) {
    return(inject_varying_columns(x, varying_vals))
  } else if (is.list(x)) {
    for (nm in names(x)) x[[nm]] <- add_varying_to_all_dfs(x[[nm]], varying_vals)
    return(x)
  }
  x
}


## Function: accumulate_results_struct
# - Args:
#   * dst: destination structure (data.frame or nested list of data.frames)
#   * src: source structure with the same shape/columns to be appended
# - Desc:
#   Recursively rbinds matching data.frames from src into dst. Lists are merged
#   by name, data.frames are row-bound. Stops if a data.frame column mismatch occurs.
accumulate_results_struct <- function(dst, src) {
  if (is.data.frame(dst) && is.data.frame(src)) {
    cols <- colnames(dst)
    if (!all(colnames(src) %in% cols)) stop("Column mismatch in accumulation (src).")
    return(rbind(dst, src))
  } else if (is.list(dst) && is.list(src)) {
    for (nm in names(src)) {
      dst[[nm]] <- accumulate_results_struct(dst[[nm]], src[[nm]])
    }
    return(dst)
  }
  return(dst)
}


## Function: load_all_quantitiative_results
# - Args:
#   * path_list: list of paths; expects $queue and other paths used downstream
#   * name_main_test: string, name of the selected main test
# - Desc:
#   Iterates through all option JSON files in the queue, loads each option’s
#   quantitative results (across batches), injects the varying-option columns,
#   accumulates everything into a single results structure, and optionally
#   removes processed option files from the queue.
load_all_quantitiative_results <- function(path_list, name_main_test) {

  ## Discover available options
  file_options_list <- sort(list.files(path_list$queue), decreasing = FALSE)
  if (length(file_options_list) == 0) {
    stop("No option files found in the queue for this test.")
  }

  cat.script_title(glue::glue("Results Loader — {TEST_SUITE}"))
  cat.section_title("Target")
  cat(glue::glue("- Test: {test_suite}/{name_main_test}\n", .trim = FALSE))
  cat(glue::glue(
    "- Options found: {length(file_options_list)}\n\n",
    .trim = FALSE
  ))

  ## Container for all loaded results
  all_results <- NULL

  ## Iterate options and load quantitative results
  for (file_options in file_options_list) {  # file_options <- file_options_list[1]
    ## Load option JSON
    test_options <- jsonlite::fromJSON(file.path(path_list$queue, file_options))

    ## Update paths for this specific option (so load_quantitative_results finds batches)
    path_list_i <- update_paths(path_list, name_main_test, test_options)

    ## Load quantitative results for this combination (all batches)
    loaded_results <- load_quantitative_results(test_options, path_list_i)

    ## Get varying options
    varying_options <- test_options$test_options$varying_options
    if (is.null(varying_options)) varying_options <- character(0)

    ## Resolve their values inside test_options
    varying_vals <- setNames(vector("list", length(varying_options)), varying_options)
    for (vn in varying_options) varying_vals[[vn]] <- resolve_option_value(vn, test_options)

    ## Add one column per varying option to each data.frame in the results
    loaded_results_with_vars <- add_varying_to_all_dfs(loaded_results, varying_vals)

    ## Accumulate results
    if (is.null(all_results)) {
      all_results <- loaded_results_with_vars
    } else {
      all_results <- accumulate_results_struct(all_results, loaded_results_with_vars)
    }

    ## Optional: keep the queue clean, mirroring previous workflow
    file.remove(file.path(path_list$queue, file_options))
  }

  return(all_results)
}
