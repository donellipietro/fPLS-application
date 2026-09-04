#!/usr/bin/env Rscript

script_file <- sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1])
if (is.na(script_file) || !nzchar(script_file)) stop("Run this script with Rscript.")
script_dir <- dirname(normalizePath(script_file))
figure_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
application_root <- normalizePath(file.path(figure_root, ".."), mustWork = TRUE)
results_root <- normalizePath(Sys.getenv("FPLS_RESULTS", unset = file.path(application_root, "results")), mustWork = TRUE)
panel_dir <- file.path(figure_root, "panels", "A_latent_scores")

suppressPackageStartupMessages({ library(ggplot2); library(grid); library(plotly) })
source(file.path(application_root, "tests", "brain", "utils", "intrinsic_slider.R"))

read_matrix <- function(path) as.matrix(suppressWarnings(read.csv(path, check.names = FALSE)))
write_pdf <- function(path, width, height, draw) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(path, width = width, height = height, family = "Arial", bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  draw()
}
write_plotly_pdf <- function(plot, path, width = 960L, height = 960L) {
  chrome <- Sys.getenv("GOOGLE_CHROME", unset = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
  magick <- Sys.which("magick")
  if (!file.exists(chrome) || !nzchar(magick)) stop("A_latent_scores requires Google Chrome and ImageMagick.")
  html <- tempfile(fileext = ".html")
  html_dir <- sub("[.]html$", "_files", html)
  png <- tempfile(fileext = ".png")
  on.exit(unlink(c(html, png, html_dir), recursive = TRUE), add = TRUE)
  htmlwidgets::saveWidget(plot, html, selfcontained = FALSE, background = "white")
  status <- system2(chrome, c(
    "--headless=new", "--allow-file-access-from-files", "--enable-webgl",
    "--ignore-gpu-blocklist", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    paste0("--window-size=", width, ",", height), "--hide-scrollbars",
    paste0("--screenshot=", png), paste0("file://", html)
  ))
  if (!identical(status, 0L) || !file.exists(png)) stop("Chrome could not rasterize the Plotly panel.")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!identical(system2(magick, c(png, "-units", "PixelsPerInch", "-density", "288", path)), 0L)) {
    stop("ImageMagick could not write the Plotly PDF.")
  }
}
write_plotly_html <- function(plot, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  htmlwidgets::saveWidget(plot, path, selfcontained = FALSE, background = "white")
}

raw_dir <- file.path(results_root, "brain", "h_stability", "h_stability_H6", "batch_1", "raw", "R1_fPLS")
batch_dir <- dirname(dirname(raw_dir))
aggregate_dir <- file.path(results_root, "brain", "aggregate", "h_stability")
required <- c(
  file.path(raw_dir, c("x_latent_scores.csv", "x_loadings_coefficients.csv", "y_loadings.csv")),
  file.path(batch_dir, "prepared_data.rds"),
  file.path(aggregate_dir, "intrinsic_fpls_scores_H3.csv"),
  file.path(aggregate_dir, "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")
)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Missing application result files: ", paste(missing, collapse = ", "))

h <- 3L
scores <- read_matrix(file.path(raw_dir, "x_latent_scores.csv"))[, seq_len(h), drop = FALSE]
x_loadings <- read_matrix(file.path(raw_dir, "x_loadings_coefficients.csv"))[, seq_len(h), drop = FALSE]
y_loadings <- as.numeric(read_matrix(file.path(raw_dir, "y_loadings.csv")))[seq_len(h)]
labels <- factor(readRDS(file.path(batch_dir, "prepared_data.rds"))$labels, levels = c("CTRL", "SCHZ"))
slider <- standardized_intrinsic_fpls_slider(scores, x_loadings, y_loadings, h)
recorded_loading <- drop(read_matrix(file.path(aggregate_dir, "intrinsic_fpls_slider_maps", "reconstruction_loading_h3.csv")))
if (max(abs(slider$loading - recorded_loading)) > 1e-12) stop("H=3 loading disagrees with the recorded aggregate map.")
score_data <- read.csv(file.path(aggregate_dir, "intrinsic_fpls_scores_H3.csv"), stringsAsFactors = FALSE)
if (!identical(as.character(score_data$group), as.character(labels)) ||
    max(abs(score_data$intrinsic_slider_coordinate - slider$coordinate)) > 1e-12) {
  stop("Saved aggregate scores do not match the native H=3 fit.")
}
threshold <- unique(score_data$intrinsic_slider_threshold)
if (length(threshold) != 1L || !is.finite(threshold)) stop("Expected one finite H=3 threshold.")
score_data$centered_slider <- score_data$intrinsic_slider_coordinate - threshold

colours <- c(CTRL = "#206400", SCHZ = "#AE017E")
latent_scores <- data.frame(t1 = score_data$z1, t2 = score_data$z2, t3 = score_data$z3,
                            group = factor(score_data$group, levels = names(colours)))
normal <- slider$unit_standardized_normal
intercept <- -threshold
plane <- expand.grid(
  t1 = seq(min(latent_scores$t1), max(latent_scores$t1), length.out = 20L),
  t2 = seq(min(latent_scores$t2), max(latent_scores$t2), length.out = 20L)
)
plane$t3 <- -(normal[1] * plane$t1 + normal[2] * plane$t2 + intercept) / normal[3]
plane <- plane[plane$t3 >= min(latent_scores$t3) & plane$t3 <= max(latent_scores$t3), , drop = FALSE]
if (nrow(plane) < 3L) stop("The clipped boundary plane has fewer than three vertices.")
latent_plot <- plot_ly(latent_scores, x = ~t1, y = ~t2, z = ~t3, color = ~group,
                         colors = unname(colours), marker = list(size = 8), showlegend = FALSE) |>
  add_markers() |>
  add_trace(data = plane, x = ~t1, y = ~t2, z = ~t3, type = "mesh3d",
            intensity = rep(0.5, nrow(plane)), opacity = 0.5,
            colorscale = list(c(0, "grey"), c(1, "grey")), showscale = FALSE,
            hoverinfo = "skip", inherit = FALSE) |>
  layout(margin = list(l = 0, r = 0, b = 0, t = 0), showlegend = FALSE,
         scene = list(camera = list(eye = list(x = 1.55, y = -0.55, z = 0.65)),
                      xaxis = list(title = "", showticklabels = FALSE),
                      yaxis = list(title = "", showticklabels = FALSE),
                      zaxis = list(title = "", showticklabels = FALSE)))
write_plotly_pdf(latent_plot, file.path(panel_dir, "latent_score_space.pdf"))
write_plotly_html(latent_plot, file.path(panel_dir, "latent_score_space.html"))

density_plot <- ggplot(score_data, aes(centered_slider, fill = group, colour = group)) +
  geom_density(alpha = 0.28, linewidth = 0.65) + geom_rug(sides = "b", alpha = 0.42, linewidth = 0.3) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.45) +
  scale_fill_manual(values = colours) + scale_colour_manual(values = colours) +
  theme_classic(base_size = 8, base_family = "Arial") +
  theme(legend.position = "none", axis.title = element_blank(), axis.text.y = element_blank(),
        axis.ticks.y = element_blank(), axis.text.x = element_text(colour = "black"),
        axis.ticks.x = element_line(), plot.margin = margin(3, 4, 3, 4, "pt"))
write_pdf(file.path(panel_dir, "projected_score_density.pdf"), 2.80, 2.55, function() print(density_plot))

write_pdf(file.path(panel_dir, "legend.pdf"), 1.25, 0.75, function() {
  grid.newpage(); grid.rect(gp = gpar(fill = "white", col = "black", lwd = 0.8))
  for (index in seq_along(colours)) {
    y <- c(0.70, 0.30)[index]
    grid.rect(0.18, y, width = 0.22, height = 0.28,
              gp = gpar(fill = grDevices::adjustcolor(colours[index], alpha.f = 0.42), col = colours[index], lwd = 1.4))
    grid.text(names(colours)[index], 0.38, y, just = "left", gp = gpar(fontfamily = "Arial", fontsize = 9.5))
  }
})
cat("A_latent_scores panels:", normalizePath(panel_dir), "\n")
