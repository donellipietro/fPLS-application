# Install the R packages used by the application runner and figure scripts.

path_entries <- function(value) {
  if (is.null(value) || !nzchar(value)) return(character())
  entries <- unlist(strsplit(value, .Platform$path.sep, fixed = TRUE))
  entries[nzchar(entries)]
}

options(repos = c(CRAN = Sys.getenv(
  "R_CRAN_REPO", unset = "https://cloud.r-project.org"
)))
user_libs <- path_entries(Sys.getenv("R_LIBS_USER", unset = ""))
site_libs <- path_entries(Sys.getenv("R_LIBS_SITE", unset = ""))
if (length(user_libs)) dir.create(user_libs[1], recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(user_libs, site_libs, .libPaths())))
install_lib <- if (length(user_libs)) user_libs[1] else .libPaths()[1]

packages <- c("ggplot2", "glue", "htmlwidgets", "jsonlite", "plotly")
missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) install.packages(missing, lib = install_lib)

# Package installation can report failures as warnings; verify the usable runtime.
missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) {
  stop(
    "Required R packages are unavailable: ", paste(missing, collapse = ", "),
    ". Check the installation errors above.", call. = FALSE
  )
}
