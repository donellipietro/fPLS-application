# Generate the supplementary slider-similarity table from saved six-component fits.

# Locate the repository and select the saved results, independently of the working directory.
script_file <- sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1])
if (is.na(script_file) || !nzchar(script_file)) stop("Run this script with Rscript.")
table_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
application_root <- normalizePath(file.path(table_root, ".."), mustWork = TRUE)
results_root <- normalizePath(
  Sys.getenv("FPLS_RESULTS", unset = file.path(application_root, "results")), mustWork = TRUE
)
brain <- file.path(results_root, "brain")
output <- file.path(table_root, "csv")

# Reuse the slider coordinates, FEM inner products and resampling summaries of the analyses.
source(file.path(application_root, "tests", "brain", "utils", "intrinsic_slider.R"))
source(file.path(application_root, "tests", "brain", "utils", "loading_stability.R"))
source(file.path(application_root, "tests", "brain", "utils", "slider_resampling.R"))
read_matrix <- function(path) as.matrix(suppressWarnings(read.csv(path, check.names = FALSE)))

# Read the complete-data H=3 reference, its mesh and the 50 archived fold comparisons.
reference_dir <- file.path(brain, "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
reference_file <- file.path(brain, "aggregate", "h_stability", "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")
reference <- read_matrix(reference_file)
points <- read_matrix(file.path(reference_dir, "points.csv"))
elements <- matrix(as.integer(read_matrix(file.path(reference_dir, "elements.csv"))), ncol = 4L)
volumes <- tetrahedral_volumes(points, elements)
old_file <- file.path(brain, "aggregate", "slider_resampling", "intrinsic_fpls_slider_resampling_vs_complete_H3.csv")
old <- read.csv(old_file)
stopifnot(nrow(old) == 50L, !anyDuplicated(old[c("repeat_index", "fold_index")]))
stopifnot(setequal(
  paste(old$repeat_index, old$fold_index),
  with(expand.grid(repeat_index = 1:10, fold_index = 1:5), paste(repeat_index, fold_index))
))
inputs <- c(reference_file, old_file, file.path(reference_dir, c("points.csv", "elements.csv")))

# Reconstruct each prefix slider from one saved fit, retaining its CTRL orientation.
read_sliders <- function(raw) {
  files <- file.path(raw, c("x_latent_scores.csv", "x_loadings_coefficients.csv", "y_loadings.csv", "params.json"))
  inputs <<- c(inputs, files)
  scores <- read_matrix(files[1])
  loadings <- read_matrix(files[2])
  response <- read_matrix(files[3])
  params <- jsonlite::fromJSON(files[4])
  stopifnot(params$n_comp == 6L, ncol(scores) == 6L, ncol(loadings) == 6L,
            nrow(loadings) == nrow(reference), all(is.finite(scores)),
            identical(params$provenance$input_md5$FEMbasis.Rds, "59433e991190b029f6f190b00c4f878a"))
  lapply(1:6, function(h) matrix(
    standardized_intrinsic_fpls_slider(scores, loadings, response, h)$loading, ncol = 1L
  ))
}

# Compare the complete-data prefixes with their H=3 reference for the first table column.
complete_sliders <- read_sliders(reference_dir)
stopifnot(isTRUE(all.equal(
  complete_sliders[[3]], reference, tolerance = 1e-12, check.attributes = FALSE
)))
complete_comparisons <- do.call(rbind, lapply(1:6, function(h) cbind(
  retained_components = h,
  mass_stability(reference, complete_sliders[[h]], elements, volumes, sign_align = FALSE)
)))
stopifnot(all(is.finite(as.matrix(complete_comparisons))))

# Compare all six prefixes of each training fit with both H=3 references.
comparisons <- do.call(rbind, lapply(seq_len(nrow(old)), function(i) {
  raw <- file.path(brain, "slider_resampling",
                   sprintf("slider_resampling_r%02d_f%02d", old$repeat_index[i], old$fold_index[i]),
                   "batch_1", "raw", "R1_fPLS")
  sliders <- read_sliders(raw)
  references <- list(within_fold_H3 = sliders[[3]], complete_data_H3 = reference)
  do.call(rbind, lapply(names(references), function(kind) {
    do.call(rbind, lapply(1:6, function(h) cbind(
      repeat_index = old$repeat_index[i], fold_index = old$fold_index[i],
      reference = kind, retained_components = h,
      mass_stability(references[[kind]], sliders[[h]], elements, volumes, sign_align = FALSE)
    )))
  }))
}))

# Check every archived H3 comparison and every within-fold H3 self-comparison.
h3 <- subset(comparisons, reference == "complete_data_H3" & retained_components == 3L)
metrics <- c("mass_correlation", "relative_mass_error", "reference_mass_norm", "candidate_mass_norm")
stopifnot(isTRUE(all.equal(as.matrix(h3[metrics]), as.matrix(old[metrics]),
                          tolerance = 1e-10, check.attributes = FALSE)))
self <- subset(comparisons, reference == "within_fold_H3" & retained_components == 3L)
stopifnot(nrow(comparisons) == 600L, all(abs(self$mass_correlation - 1) < 1e-12),
          all(self$relative_mass_error == 0), all(is.finite(as.matrix(comparisons[metrics]))))

# Summarize the 50 comparisons at each prefix using the original analysis statistics.
summary <- do.call(rbind, lapply(split(comparisons, list(comparisons$reference, comparisons$retained_components)), function(x) {
  result <- slider_resampling_summary(x)
  result$metric <- c("rho_H", "e_H")
  cbind(reference = x$reference[1], retained_components = x$retained_components[1], result)
}))

# Assemble the three manuscript columns, preserving full-precision medians and quartiles.
paper_table <- data.frame(
  retained_components = complete_comparisons$retained_components,
  complete_data_rho_H = complete_comparisons$mass_correlation
)
for (reference_kind in c("complete_data_H3", "within_fold_H3")) {
  rows <- subset(summary, reference == reference_kind & metric == "rho_H")
  rows <- rows[match(paper_table$retained_components, rows$retained_components), ]
  for (statistic in c("median", "q25", "q75")) {
    paper_table[[paste0("training_folds_vs_", reference_kind, "_", statistic)]] <- rows[[statistic]]
  }
}
stopifnot(all(is.finite(as.matrix(paper_table))))

# Export the manuscript table and the numerical comparisons supporting it.
dir.create(output, recursive = TRUE, showWarnings = FALSE)
write.csv(paper_table, file.path(output, "slider_similarity.csv"), row.names = FALSE)
write.csv(comparisons, file.path(output, "comparisons_by_fold_and_H.csv"), row.names = FALSE)
write.csv(summary, file.path(output, "summary_by_H.csv"), row.names = FALSE)
write.csv(data.frame(path = inputs, md5 = unname(tools::md5sum(inputs))),
          file.path(output, "saved_fit_inputs.csv"), row.names = FALSE)
print(paper_table, row.names = FALSE)
cat("Wrote the slider-similarity table; verified 50 archived H3 comparisons and 50 self-comparisons.\n")
