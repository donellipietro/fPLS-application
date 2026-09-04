#!/usr/bin/env Rscript

suppressMessages(library(cowplot))
suppressMessages(library(ggplot2))
suppressMessages(library(scatterplot3d))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: generate_manuscript_figures.R brain.png output-directory")
brain_file <- normalizePath(args[[1]], mustWork = TRUE)
output_dir <- normalizePath(args[[2]], mustWork = TRUE)
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1]])
root <- normalizePath(file.path(dirname(script_file), "../.."), mustWork = TRUE)
aggregate <- file.path(root, "results", "brain", "aggregate")
scores <- read.csv(file.path(aggregate, "h_stability", "intrinsic_fpls_scores_H3.csv"))
coordinates <- read.csv(file.path(
  aggregate, "h_stability", "intrinsic_fpls_slider_coordinates_by_H.csv"
))
resampling <- read.csv(file.path(
  aggregate, "slider_resampling", "intrinsic_fpls_slider_resampling_vs_complete_H3.csv"
))
hmin <- read.csv(file.path(
  aggregate, "slider_resampling", "slider_resampling_Hmin_distribution.csv"
))
held_out <- read.csv(file.path(
  aggregate, "slider_resampling", "slider_resampling_test_explained_structure_by_fold.csv"
))

colors <- c(CTRL = "#3F7D20", SCHZ = "#C51B7D")
q <- as.numeric(coordinates[coordinates$retained_components == 3L, paste0("q_t", 1:3)])
threshold <- unique(scores$intrinsic_slider_threshold)
latent_file <- tempfile(fileext = ".png")
png(latent_file, width = 1200, height = 900, res = 150, bg = "white")
plot <- scatterplot3d(
  scores[c("z1", "z2", "z3")],
  color = unname(colors[as.character(scores$group)]),
  pch = 19,
  cex.symbols = 0.7,
  grid = TRUE,
  box = FALSE,
  angle = 55,
  xlab = expression(z[1]),
  ylab = expression(z[2]),
  zlab = expression(z[3]),
  main = "Standardized latent score space"
)
plot$plane3d(threshold / q[3], -q[1] / q[3], -q[2] / q[3], col = "grey45", lty = 2)
legend("topleft", names(colors), col = colors, pch = 19, bty = "n", cex = 0.8)
dev.off()
latent_plot <- ggdraw() + draw_image(latent_file)

distribution_plot <- ggplot(
  scores,
  aes(intrinsic_slider_coordinate, fill = group, colour = group)
) +
  geom_density(alpha = 0.28, linewidth = 0.65) +
  geom_rug(alpha = 0.45) +
  geom_vline(xintercept = threshold, linetype = 2) +
  scale_fill_manual(values = colors) +
  scale_colour_manual(values = colors) +
  labs(
    title = "Projected fPLS score",
    x = bquote(plain("\U0001D4AE")[H == 3]),
    y = "Density",
    fill = NULL,
    colour = NULL
  ) +
  theme_bw(base_size = 10) +
  theme(
    legend.position = "top",
    axis.title.x = element_text(family = "STIX Two Math")
  )

scores_figure <- plot_grid(
  latent_plot,
  distribution_plot,
  rel_widths = c(1.05, 0.9),
  nrow = 1
)
ggsave(
  file.path(output_dir, "application_scores.pdf"),
  scores_figure,
  width = 10,
  height = 4.2,
  device = cairo_pdf
)

brain_plot <- ggdraw() +
  draw_image(brain_file) +
  draw_label(expression(f[H]^PLS ~~ (H == 3)), x = 0.5, y = 0.98, vjust = 1, size = 13)

primary <- plot_grid(
  latent_plot,
  distribution_plot,
  brain_plot,
  labels = c("a", "b", "c"),
  rel_widths = c(1.05, 0.9, 1.25),
  nrow = 1
)
ggsave(
  file.path(output_dir, "application_intrinsic_slider.pdf"),
  primary,
  width = 13,
  height = 4.2,
  device = cairo_pdf
)

hmin_plot <- ggplot(hmin, aes(factor(first_H), proportion)) +
  geom_col(fill = "#007C91", width = 0.62) +
  geom_text(aes(label = training_fits), vjust = -0.4, size = 3.2) +
  scale_y_continuous(limits = c(0, 1.08), labels = scales::percent) +
  labs(x = "First perfectly separating training prefix", y = "Training fits") +
  theme_bw(base_size = 10)

metric_plot <- function(column, label, color) {
  ggplot(resampling, aes(x = "", y = .data[[column]])) +
    geom_boxplot(width = 0.28, outlier.shape = NA, colour = color) +
    geom_jitter(width = 0.08, alpha = 0.55, colour = color, size = 1.4) +
    labs(x = NULL, y = label) +
    theme_bw(base_size = 10) +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
}
stability <- plot_grid(
  hmin_plot,
  metric_plot("mass_correlation", expression(rho), "#3F7D20"),
  metric_plot("relative_mass_error", expression(e), "#C51B7D"),
  labels = c("a", "b", "c"),
  nrow = 1
)
ggsave(
  file.path(output_dir, "application_slider_resampling.pdf"),
  stability,
  width = 10.5,
  height = 3.7,
  device = cairo_pdf
)

held_out_long <- rbind(
  data.frame(held_out[c("repeat_index", "fold_index", "retained_components")], metric = "X", value = held_out$X_variance_explained),
  data.frame(held_out[c("repeat_index", "fold_index", "retained_components")], metric = "Y", value = held_out$Y_variance_explained),
  data.frame(held_out[c("repeat_index", "fold_index", "retained_components")], metric = "XY", value = held_out$XY_cross_covariance_explained)
)
held_out_summary <- aggregate(
  value ~ retained_components + metric,
  held_out_long,
  function(values) c(median = median(values), q25 = quantile(values, 0.25), q75 = quantile(values, 0.75))
)
held_out_summary <- cbind(held_out_summary[1:2], as.data.frame(held_out_summary$value))
names(held_out_summary)[3:5] <- c("median", "q25", "q75")
held_out_plot <- ggplot(
  held_out_long,
  aes(retained_components, value, group = interaction(repeat_index, fold_index))
) +
  geom_line(alpha = 0.16, linewidth = 0.3, colour = "grey35") +
  geom_ribbon(
    data = held_out_summary,
    aes(x = retained_components, ymin = q25, ymax = q75, group = NULL),
    inherit.aes = FALSE,
    fill = "#007C91",
    alpha = 0.2
  ) +
  geom_line(
    data = held_out_summary,
    aes(x = retained_components, y = median, group = NULL),
    inherit.aes = FALSE,
    colour = "#007C91",
    linewidth = 0.8
  ) +
  facet_wrap(~metric, scales = "free_y", labeller = as_labeller(c(
    X = "X variance", Y = "Y variance", XY = "X--Y cross-covariance"
  ))) +
  scale_x_continuous(breaks = 1:6) +
  labs(x = "Retained components H", y = "Held-out explained structure") +
  theme_bw(base_size = 10)
ggsave(
  file.path(output_dir, "application_heldout_structure.pdf"),
  held_out_plot,
  width = 10.5,
  height = 3.7,
  device = cairo_pdf
)
