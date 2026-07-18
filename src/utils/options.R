#' Find the path to a named field inside a nested list.
#'
#' @param x Input object.
#' @param target Field name to locate.
#' @param path File or directory path.
#' @return The value produced by `find_name_path`.
find_name_path <- function(x, target, path = character()) {
  if (!is.list(x)) return(list(found = FALSE))
  nms <- names(x)
  for (i in seq_along(x)) {
    nm <- nms[i]
    newpath <- c(path, nm)
    if (identical(nm, target)) return(list(found = TRUE, path = newpath))
    res <- find_name_path(x[[i]], target, newpath)
    if (isTRUE(res$found)) return(res)
  }
  list(found = FALSE)
}
#' Read a nested-list value by path.
#'
#' @param x Input object.
#' @param path File or directory path.
#' @return The value produced by `get_by_path`.
get_by_path <- function(x, path) {
  Reduce(function(acc, key) acc[[key]], path, init = x)
}
#' Set a nested-list value by path.
#'
#' @param x Input object.
#' @param path File or directory path.
#' @param value Value to process.
#' @return The value produced by `set_by_path`.
set_by_path <- function(x, path, value) {
  if (length(path) == 1L) {
    x[[path]] <- value
  } else {
    x[[path[1L]]] <- set_by_path(x[[path[1L]]], path[-1L], value)
  }
  x
}
#' Expand selected option fields into a Cartesian grid of option objects.
#'
#' @param options Nested option list.
#' @param by Field names to expand as a Cartesian product.
#' @param formatters Optional named formatting functions for generated names.
#' @param name_fun Optional function used to generate option names.
#' @return The value produced by `explode_options`.
explode_options <- function(options, by, formatters = NULL, name_fun = NULL) {

  ## Locate paths for each 'by' field and get their vectors
  paths <- lapply(by, function(nm) {
    res <- find_name_path(options, nm)
    if (!isTRUE(res$found)) stop(glue::glue("Field '{nm}' not found in options."))
    res$path
  })
  names(paths) <- by

  ## Extract values for each field in 'by'
  grids <- lapply(by, function(nm) {
    val <- get_by_path(options, paths[[nm]])
    if (is.null(val)) stop(glue::glue("Field '{nm}' is NULL."))
    if (!is.atomic(val)) stop(glue::glue("Field '{nm}' must be an atomic vector for 'by'."))
    val
  })
  names(grids) <- by

  ## Build the Cartesian product
  comb <- do.call(expand.grid, c(grids, stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE))

  ## Create one option list per combination
  out <- vector("list", nrow(comb))
  for (i in seq_len(nrow(comb))) {
    opt_i <- options

    ## Substitute scalars for the 'by' fields
    for (nm in by) {
      v <- comb[[nm]][i]
      if (is.list(v)) v <- v[[1L]]  # safeguard
      opt_i <- set_by_path(opt_i, paths[[nm]], v)
    }

    ## Build or refresh name_test
    if (!is.null(name_fun)) {
      opt_i$name_test <- name_fun(opt_i, comb[i, , drop = FALSE])
    } else if (is.null(opt_i$name_test)) {
      ## Default name: only 'by' fields with optional formatting
      parts <- mapply(function(nm, val) {
        vv <- val
        if (!is.null(formatters) && !is.null(formatters[[nm]]))
          vv <- formatters[[nm]](vv)
        glue::glue("{nm}_{as.character(vv)}")
      }, nm = by, val = as.list(comb[i, by, drop = FALSE]))
      opt_i$name_test <- glue::glue_collapse(unlist(parts), sep = "_")
    }

    out[[i]] <- opt_i
  }

  attr(out, "combinations") <- comb
  out
}
#' Write expanded option objects to JSON files.
#'
#' @param options_list List of option objects to write.
#' @param dir Output directory for JSON files.
#' @param name_field Field containing the output filename stem.
#' @param pretty Whether JSON output should be pretty-printed.
#' @param auto_unbox Whether scalar values should be unboxed in JSON.
#' @return The value produced by `write_options_json`.
write_options_json <- function(options_list, dir, name_field = "name_test",
                               pretty = TRUE, auto_unbox = TRUE) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  unlink(list.files(dir, pattern = "\\.json$", full.names = TRUE))
  for (opt in options_list) {
    nm <- opt[[name_field]]
    if (is.null(nm)) stop("Missing 'name_field' in one options element.")
    write_json(
      opt,
      file.path(dir, glue::glue("{nm}.json")),
      pretty = pretty,
      auto_unbox = auto_unbox,
      digits = NA
    )
  }
}
