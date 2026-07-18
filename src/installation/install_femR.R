#' Split a path-list environment variable into usable path entries.
#'
#' @param value Value to process.
#' @return The value produced by `path_entries`.
path_entries <- function(value) {
  if (is.null(value) || !nzchar(value)) return(character())

  entries <- unlist(strsplit(value, .Platform$path.sep, fixed = TRUE))
  entries[nzchar(entries)]
}

r_cran_repo <- Sys.getenv("R_CRAN_REPO", unset = "https://cloud.r-project.org")
options(repos = c(CRAN = r_cran_repo))

user_libs <- path_entries(Sys.getenv("R_LIBS_USER", unset = ""))
site_libs <- path_entries(Sys.getenv("R_LIBS_SITE", unset = ""))

if (length(user_libs) > 0) {
  dir.create(user_libs[1], recursive = TRUE, showWarnings = FALSE)
}

.libPaths(unique(c(user_libs, site_libs, .libPaths())))
install_lib <- if (length(user_libs) > 0) user_libs[1] else .libPaths()[1]

cat("R library paths:\n")
print(.libPaths())
cat("CRAN mirror:", getOption("repos")[["CRAN"]], "\n")

cran_packages <- c(
  "dplyr", "ggplot2", "glue", "gridExtra", "jsonlite", "RColorBrewer", "tidyr"
)
missing_packages <- cran_packages[
  !vapply(cran_packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, lib = install_lib)
}

if (requireNamespace("femR", quietly = TRUE)) {
  cat("The package femR is already installed\n")
  quit(save = "no", status = 0)
}

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", lib = install_lib)
}

remotes::install_github(
  "fdaPDE/femR",
  ref = "stable",
  lib = install_lib,
  upgrade = "never"
)
