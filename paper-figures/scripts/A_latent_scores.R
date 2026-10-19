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
score_matrix <- as.matrix(latent_scores[, c("t1", "t2", "t3")])
bounds <- apply(score_matrix, 2L, range)
plane_center <- colMeans(bounds)
plane_center <- plane_center - (sum(normal * plane_center) + intercept) * normal
# Use orthogonal in-plane directions so the four corners form a rectangle.
horizontal <- c(-normal[2], normal[1], 0)
horizontal <- horizontal / sqrt(sum(horizontal^2))
vertical <- c(-normal[3] * horizontal[2], normal[3] * horizontal[1],
              normal[1] * horizontal[2] - normal[2] * horizontal[1])
basis <- cbind(horizontal, vertical)
box_corners <- as.matrix(expand.grid(lapply(seq_len(3L), function(j) bounds[, j])))
half_size <- apply(abs(sweep(box_corners, 2L, plane_center) %*% basis), 2L, max)
offsets <- rbind(c(-1, -1), c(1, -1), c(1, 1), c(-1, 1)) %*% diag(half_size) %*% t(basis)
plane <- sweep(offsets, 2L, plane_center, "+")
edges <- plane[c(2L, 3L, 4L, 1L), ] - plane
stopifnot(max(abs(plane %*% normal + intercept)) < 1e-10,
          max(abs(rowSums(edges * edges[c(2L, 3L, 4L, 1L), ]))) < 1e-10)
plane <- setNames(as.data.frame(plane), c("t1", "t2", "t3"))
latent_plot <- plot_ly(latent_scores, x = ~t1, y = ~t2, z = ~t3, color = ~group,
                         colors = unname(colours), marker = list(size = 8), showlegend = FALSE) |>
  add_markers() |>
  add_trace(data = plane, x = ~t1, y = ~t2, z = ~t3, type = "mesh3d",
            i = c(0L, 0L), j = c(1L, 2L), k = c(2L, 3L),
            intensity = rep(0.5, nrow(plane)), opacity = 0.5,
            colorscale = list(c(0, "grey"), c(1, "grey")),
            showscale = FALSE,
            hoverinfo = "skip", inherit = FALSE) |>
  layout(margin = list(l = 0, r = 0, b = 0, t = 0), showlegend = FALSE,
         scene = list(camera = list(
                        eye = list(x = 1.6171387939700241, y = -1.533153007625624, z = -0.09033674289559722),
                        up = list(x = -0.01795006102026315, y = 0.039932337130336844, z = -0.9990411421761758),
                        center = list(x = 0, y = 0, z = 0),
                        projection = list(type = "perspective")),
                      # Fix the original score ranges so the larger plane does not zoom out the points.
                      xaxis = list(title = "", showticklabels = FALSE,
                                   range = bounds[, 1L] + c(-1, 1) * diff(bounds[, 1L]) / 32),
                      yaxis = list(title = "", showticklabels = FALSE,
                                   range = bounds[, 2L] + c(-1, 1) * diff(bounds[, 2L]) / 32),
                      zaxis = list(title = "", showticklabels = FALSE,
                                   range = bounds[, 3L] + c(-1, 1) * diff(bounds[, 3L]) / 32)))
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
write_pdf(file.path(panel_dir, "projected_score_density.pdf"), 2.80, 57 / 25.4, function() print(density_plot))

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
