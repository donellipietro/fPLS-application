#!/usr/bin/env Rscript

script_file <- sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1])
if (is.na(script_file) || !nzchar(script_file)) stop("Run this script with Rscript.")
script_dir <- dirname(normalizePath(script_file))
figure_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
application_root <- normalizePath(file.path(figure_root, ".."), mustWork = TRUE)
results_root <- normalizePath(Sys.getenv("FPLS_RESULTS", unset = file.path(application_root, "results")), mustWork = TRUE)
panel_dir <- file.path(figure_root, "panels", "A_slider")

source(file.path(application_root, "tests", "brain", "utils", "intrinsic_slider.R"))
source(file.path(application_root, "tests", "brain", "utils", "paraview_export.R"))
read_matrix <- function(path) as.matrix(suppressWarnings(read.csv(path, check.names = FALSE)))

raw_dir <- file.path(results_root, "brain", "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
batch_dir <- dirname(dirname(raw_dir))
aggregate_dir <- file.path(results_root, "brain", "aggregate", "h_stability")
required <- c(
  file.path(raw_dir, c("points.csv", "elements.csv", "x_latent_scores.csv", "x_loadings_coefficients.csv", "y_loadings.csv", "functional_mean_locations.csv")),
  file.path(batch_dir, "prepared_data.rds"), file.path(aggregate_dir, "intrinsic_fpls_scores_H3.csv"),
  file.path(aggregate_dir, "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")
)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Missing application result files: ", paste(missing, collapse = ", "))

h <- 3L
points <- read_matrix(file.path(raw_dir, "points.csv")); elements <- read_matrix(file.path(raw_dir, "elements.csv"))
scores <- read_matrix(file.path(raw_dir, "x_latent_scores.csv"))[, seq_len(h), drop = FALSE]
x_loadings <- read_matrix(file.path(raw_dir, "x_loadings_coefficients.csv"))[, seq_len(h), drop = FALSE]
y_loadings <- as.numeric(read_matrix(file.path(raw_dir, "y_loadings.csv")))[seq_len(h)]
functional_mean <- drop(read_matrix(file.path(raw_dir, "functional_mean_locations.csv")))
labels <- factor(readRDS(file.path(batch_dir, "prepared_data.rds"))$labels, levels = c("CTRL", "SCHZ"))
slider <- standardized_intrinsic_fpls_slider(scores, x_loadings, y_loadings, h)
accepted_loading <- drop(read_matrix(file.path(aggregate_dir, "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")))
if (max(abs(slider$loading - accepted_loading)) > 1e-12) stop("H=3 loading disagrees with the accepted aggregate map.")
score_data <- read.csv(file.path(aggregate_dir, "intrinsic_fpls_scores_H3.csv"), stringsAsFactors = FALSE)
if (!identical(as.character(score_data$group), as.character(labels)) ||
    max(abs(score_data$intrinsic_slider_coordinate - slider$coordinate)) > 1e-12) {
  stop("Saved aggregate scores do not match the native H=3 fit.")
}
threshold <- unique(score_data$intrinsic_slider_threshold)
if (length(threshold) != 1L || !is.finite(threshold)) stop("Expected one finite H=3 threshold.")

state_scores <- c(SCHZ = mean(score_data$intrinsic_slider_coordinate[score_data$group == "SCHZ"]),
                  critical = threshold,
                  CTRL = mean(score_data$intrinsic_slider_coordinate[score_data$group == "CTRL"]))
state_fields <- lapply(state_scores, function(value) functional_mean + value * accepted_loading)
if (any(vapply(state_fields, function(value) length(value) != nrow(points) || any(!is.finite(value)), logical(1)))) {
  stop("Reconstructed connectivity states are not finite mesh-node fields.")
}
temporary_vtu <- tempfile(fileext = ".vtu")
on.exit(unlink(temporary_vtu), add = TRUE)
write_tetrahedral_vtu(temporary_vtu, points, elements, setNames(state_fields, paste0("state_", names(state_fields))))
status <- system2(Sys.getenv("PVPYTHON", unset = "pvpython"), c(file.path(script_dir, "A_slider.py"), temporary_vtu, panel_dir))
if (!identical(status, 0L)) stop("A_slider ParaView export failed with status ", status)
write.csv(data.frame(state = names(state_scores), slider_coordinate = unname(state_scores),
                     threshold_centered_slider = unname(state_scores - threshold)),
          file.path(panel_dir, "state_definitions.csv"), row.names = FALSE)
cat("A_slider panels:", normalizePath(panel_dir), "\n")
