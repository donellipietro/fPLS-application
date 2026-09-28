# Saved-fit postprocessing only. Run from the repository root:
# Rscript tests/brain/postprocess_slider_resampling_by_H.R RESULTS_ROOT OUTPUT_DIR
suppressPackageStartupMessages(library(ggplot2))
source("tests/brain/utils/intrinsic_slider.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/slider_resampling.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("expected RESULTS_ROOT and OUTPUT_DIR")
brain <- file.path(args[1], "brain")
output <- args[2]
read_matrix <- function(path) as.matrix(suppressWarnings(read.csv(path, check.names = FALSE)))
reference_dir <- file.path(brain, "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
reference_file <- file.path(brain, "aggregate", "h_stability", "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")
reference <- read_matrix(reference_file)
points <- read_matrix(file.path(reference_dir, "points.csv"))
elements <- matrix(as.integer(read_matrix(file.path(reference_dir, "elements.csv"))), ncol = 4L)
volumes <- tetrahedral_volumes(points, elements)
old_file <- file.path(brain, "aggregate", "slider_resampling", "intrinsic_fpls_slider_resampling_vs_complete_H3.csv")
old <- read.csv(old_file)
stopifnot(nrow(old) == 50L, !anyDuplicated(old[c("repeat_index", "fold_index")]))
inputs <- c(reference_file, old_file, file.path(reference_dir, c("points.csv", "elements.csv")))
comparisons <- do.call(rbind, lapply(seq_len(nrow(old)), function(i) {
  raw <- file.path(brain, "slider_resampling",
                   sprintf("slider_resampling_r%02d_f%02d", old$repeat_index[i], old$fold_index[i]),
                   "batch_1", "raw", "R1_fPLS")
  files <- file.path(raw, c("x_latent_scores.csv", "x_loadings_coefficients.csv", "y_loadings.csv", "params.json"))
  inputs <<- c(inputs, files)
  scores <- read_matrix(files[1])
  loadings <- read_matrix(files[2])
  response <- read_matrix(files[3])
  params <- jsonlite::fromJSON(files[4])
  stopifnot(params$n_comp == 6L, ncol(scores) == 6L, ncol(loadings) == 6L,
            nrow(loadings) == nrow(reference), all(is.finite(scores)),
            identical(params$provenance$input_md5$FEMbasis.Rds, "59433e991190b029f6f190b00c4f878a"))
  sliders <- lapply(1:6, function(h) matrix(
    standardized_intrinsic_fpls_slider(scores, loadings, response, h)$loading, ncol = 1L
  ))
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
summary <- do.call(rbind, lapply(split(comparisons, list(comparisons$reference, comparisons$retained_components)), function(x) {
  result <- slider_resampling_summary(x)
  result$metric <- c("rho_H", "e_H")
  cbind(reference = x$reference[1], retained_components = x$retained_components[1], result)
}))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
write.csv(comparisons, file.path(output, "comparisons_by_fold_and_H.csv"), row.names = FALSE)
write.csv(summary, file.path(output, "summary_by_H.csv"), row.names = FALSE)
write.csv(data.frame(path = inputs, md5 = unname(tools::md5sum(inputs))),
          file.path(output, "saved_fit_inputs.csv"), row.names = FALSE)
plot_values <- rbind(
  transform(comparisons, metric = "rho_H", value = mass_correlation),
  transform(comparisons, metric = "e_H", value = relative_mass_error)
)
p <- ggplot(plot_values, aes(factor(retained_components), value)) +
  geom_boxplot(fill = "#81C7CB", outlier.size = 1) +
  facet_wrap(reference ~ metric, scales = "free_y", ncol = 2) +
  labs(x = "Retained components H", y = "FEM comparison with H=3",
       caption = "50 training fits (10 repeats x 5 folds); no held-out performance evaluation") + theme_bw()
if (capabilities("cairo")) options(bitmapType = "cairo")
for (ext in c("png", "pdf")) ggsave(file.path(output, paste0("slider_stability_by_H.", ext)),
                                     p, width = 9, height = 7, dpi = 180)
print(summary[c("reference", "retained_components", "metric", "mean", "sd")], row.names = FALSE)
cat("PASS: 50 archived H3 comparisons reproduced; 50 H3 self-comparisons verified. No refit.\n")
