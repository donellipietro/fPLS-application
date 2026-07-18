# = ========================================================================== =
# - Script: plotting_utils.R
# - Desc: Utility functions for plotting, including standard plot settings
#         and point visualization over 2D domains or meshes.
# = ========================================================================== =

.plotting_utils_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, mustWork = FALSE)),
  error = function(e) file.path("src", "utils")
)
.paraview_colormaps_file <- file.path(.plotting_utils_dir, "paraview_colormaps.json")
if (!file.exists(.paraview_colormaps_file)) {
  .paraview_colormaps_file <- file.path("src", "utils", "paraview_colormaps.json")
}
.paraview_colormaps_cache <- NULL

paraview_colormap_names <- function() {
  names(paraview_colormaps())
}

paraview_colormaps <- function() {
  if (!is.null(.paraview_colormaps_cache)) return(.paraview_colormaps_cache)
  if (!file.exists(.paraview_colormaps_file)) {
    stop(glue::glue("ParaView colormap preset file not found: {.paraview_colormaps_file}"))
  }

  presets <- jsonlite::fromJSON(.paraview_colormaps_file, simplifyVector = FALSE)
  maps <- lapply(presets, function(preset) {
    if (!is.null(preset$RGBPoints)) {
      points <- matrix(as.numeric(preset$RGBPoints), ncol = 4, byrow = TRUE)
      colours <- grDevices::rgb(points[, 2], points[, 3], points[, 4])
      values <- points[, 1]
      span <- range(values)
      values <- if (diff(span) == 0) NULL else (values - span[1]) / diff(span)
    } else if (!is.null(preset$IndexedColors)) {
      points <- matrix(as.numeric(preset$IndexedColors), ncol = 3, byrow = TRUE)
      colours <- grDevices::rgb(points[, 1], points[, 2], points[, 3])
      values <- NULL
    } else {
      colours <- character()
      values <- NULL
    }
    list(name = preset$Name, colours = colours, values = values)
  })
  names(maps) <- vapply(maps, function(map) map$name, character(1))

  .paraview_colormaps_cache <<- maps
  maps
}

paraview_colormap <- function(name = "Cool to Warm (Extended)", n = NULL,
                              reverse = FALSE, values = FALSE) {
  maps <- paraview_colormaps()
  key <- names(maps)[tolower(names(maps)) == tolower(name)][1]
  if (is.na(key)) {
    stop(glue::glue(
      "Unknown ParaView colormap: {name}. Available colormaps: ",
      "{glue::glue_collapse(paraview_colormap_names(), sep = ', ')}"
    ))
  }

  colours <- maps[[key]]$colours
  map_values <- maps[[key]]$values
  if (!is.null(n)) {
    colours <- grDevices::colorRampPalette(colours)(n)
    map_values <- NULL
  }
  if (reverse) {
    colours <- rev(colours)
    map_values <- if (!is.null(map_values)) rev(1 - map_values) else NULL
  }

  if (values) {
    return(list(colours = colours, values = map_values))
  }
  colours
}

as_ggplot_palette <- function(palette) {
  if (is.null(palette)) return(NULL)
  if (is.list(palette)) return(palette)
  if (length(palette) == 1L && !grepl("^#", palette)) {
    return(paraview_colormap(palette, values = TRUE))
  }
  list(colours = palette, values = NULL)
}

cool_to_warm_extended_palette <- paraview_colormap("Cool to Warm (Extended)")


## Function: std_plot_settings
# - Args:
#   * NONE
# - Desc:
#   Returns a ggplot2 theme with standard visual settings for general-purpose
#   plots, using a clean black-and-white background and centered bold titles.
std_plot_settings <- function() {

  ## Create standard theme
  standard_plot_settings <- theme_bw() +
    theme(
      text = element_text(size = 12),
      plot.title = element_text(
        color = "black",
        face = "bold",
        size = 14,
        hjust = 0.5,
        vjust = 1
      ),
      legend.position = "top",
    )
}


## Function: std_plot_settings_fields
# - Args:
#   * NONE
# - Desc:
#   Returns a ggplot2 theme optimized for visualizing spatial fields.
#   Removes axes, ticks, and grid lines, keeping only essential elements
#   such as color legend and plot title.
std_plot_settings_fields <- function() {

  ## Create theme for field visualization
  standard_plot_settings_fields <- theme_minimal() +
    theme(
      text = element_text(size = 12),
      plot.title = element_text(
        color = "black",
        face = "bold",
        size = 14,
        hjust = 0.5,
        vjust = 1
      ),
      axis.title.x = element_blank(),
      axis.title.y = element_blank(),
      axis.text.x = element_blank(),
      axis.text.y = element_blank(),
      axis.ticks.x = element_blank(),
      axis.ticks.y = element_blank(),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      legend.text.position = "top",
      legend.title = element_blank(),
      legend.text = element_text(angle = 45, hjust = 1)
    )
}


# Function: std_plot_settings_curves
# - Args:
#   * NONE
# - Desc:
#   Returns a ggplot2 theme optimized for visualizing curves
std_plot_settings_curves <- function() {

  ## Create theme for field visualization
  standard_plot_settings_fields <- theme_light() +
    theme(
      text = element_text(size = 12),
      plot.title = element_text(
        color = "black",
        face = "bold",
        size = 14,
        hjust = 0.5,
        vjust = 1
      ),
      axis.title.x = element_blank(),
      axis.title.y = element_blank(),
      # axis.text.x = element_blank(),
      # axis.text.y = element_blank(),
      # axis.ticks.x = element_blank(),
      # axis.ticks.y = element_blank(),
      # panel.grid.major = element_blank(),
      # panel.grid.minor = element_blank(),
      legend.text.position = "top",
      legend.title = element_blank(),
      legend.text = element_text(angle = 45, hjust = 1)
    )
}


## Function: plot.points
# - Args:
#   * locations: matrix or data.frame with 2 columns (x, y) for point coordinates
#   * boundary: optional SpatialPolygons or data.frame defining a boundary
#   * group: optional vector assigning each point to a group
#   * group_name: string, name of the legend for groups (default: "Groups")
#   * group_colors: optional named vector of colors for each group
#   * group_labels: optional vector of labels for each group
#   * size: numeric, point size
#   * LEGEND: logical, whether to display the legend (default: FALSE)
# - Desc:
#   Plots 2D points (locations) with optional grouping and boundary outline.
#   Automatically assigns colors and labels when not provided, and ensures
#   fixed aspect ratio for spatial accuracy.
plot.points <- function(locations, boundary = NULL, group = NULL,
                        group_name = "Groups", group_colors = NULL, group_labels = NULL,
                        size = 1, LEGEND = FALSE) {

  ## Assemble data
  if (is.null(group)) {
    group <- rep(0, nrow(locations))
  }
  data <- data.frame(locations, group)
  colnames(data) <- c("x", "y", "Group")

  ## Grouping
  group_levels <- unique(data$Group)
  if (is.null(group_labels)) {
    group_labels <- group_levels
  }

  ## Define association between group labels and colors
  if (is.null(group_colors)) {
    if (length(group_labels) > 1) {
      group_colors <- rainbow(length(group_labels))
    } else {
      group_colors <- c("#000000")
    }
  }
  names(group_colors) <- group_labels

  ## Refactor categorical variables
  data <- data %>%
    mutate(Group = factor(Group, levels = group_levels, labels = group_labels))

  ## Build plot
  plot <- ggplot() +
    geom_point(data = data, aes(x = x, y = y, color = Group), size = size) +
    coord_fixed() +
    scale_color_manual(
      name = group_name,
      values = group_colors,
      labels = group_labels
    )

  ## Add boundary if provided
  if (!is.null(boundary)) {
    plot <- plot +
      geom_polygon(
        data = fortify(boundary),
        aes(x = long, y = lat),
        fill = "transparent",
        color = "black",
        linewidth = 1
      )
  }

  ## Add or remove legend
  if (!LEGEND) {
    plot <- plot + guides(color = "none")
  }

  return(plot)
}

# --- Helper: coerce to matrix form ---
as_curve_matrix <- function(locations, obj, prefix = "curve") {
  if (is.null(obj)) return(NULL)

  if (is.list(obj)) {
    cols <- lapply(obj, function(z) {
      z <- as.numeric(z)
      if (length(z) != length(locations))
        stop("All list elements must have length equal to length(locations).")
      z
    })
    M <- do.call(cbind, cols)
    cn <- names(obj)
    if (is.null(cn)) cn <- glue::glue("{prefix}{seq_len(ncol(M))}")
    colnames(M) <- cn
    return(M)
  }

  if (is.vector(obj) && !is.list(obj)) {
    if (length(obj) != length(locations))
      stop("'f' (vector) must have length equal to length(locations).")
    M <- matrix(as.numeric(obj), ncol = 1)
    colnames(M) <- prefix
    return(M)
  }

  if (is.matrix(obj)) {
    if (nrow(obj) != length(locations))
      stop("'f' (matrix) must have nrow equal to length(locations).")
    M <- obj
    if (is.null(colnames(M)))
      colnames(M) <- glue::glue("{prefix}{seq_len(ncol(M))}")
    return(M)
  }

  stop("Unsupported type for curves. Use vector, matrix, or list of vectors.")
}

# --- Helper: long data frame for ggplot ---
to_long <- function(x, M) {
  k <- ncol(M)
  data.frame(
    x = rep(x, times = k),
    y = as.numeric(M),
    curve = rep(colnames(M), each = length(x)),
    stringsAsFactors = FALSE
  )
}

plot.curve <- function(locations, f, true = NULL, limits = NULL, LEGEND = FALSE, colors = "black") {

  ## Handle null input
  if (is.null(f)) {
    return(ggplot() + theme_void())
  }

  # --- Main plot ---
  M <- as_curve_matrix(locations, f, prefix = "curve")
  data_long <- to_long(locations, M)

  plot <- ggplot(data_long, aes(x = x, y = y, group = curve)) +
    geom_line(color = colors)

  # --- True curves (green + thicker + dotted) ---
  if (!is.null(true)) {
    Tm <- as_curve_matrix(locations, true, prefix = "true")
    data_true <- to_long(locations, Tm)

    if (ncol(M) > 1) {
      # multiple curves → make true curve stand out
      plot <- plot + geom_line(
        data = data_true,
        aes(x = x, y = y),
        linetype = "dashed",
        color = "green",
        linewidth = 0.8
      )
    } else {
      # single curve → normal black dotted
      plot <- plot + geom_line(
        data = data_true,
        aes(x = x, y = y),
        linetype = "dotted",
        color = "darkgreen",
        linewidth = 0.8
      )
    }
  }

  # --- Y limits ---
  if (!is.null(limits)) {
    plot <- plot + ylim(limits[1], limits[2])
  }

  # --- Legend control ---
  if (!LEGEND) {
    plot <- plot + theme(legend.position = "none")
  }

  return(plot)
}

plot.curve_points <- function(locations, f, true = NULL, size = 1, limits = NULL) {

  ## Handle null input
  if (is.null(f)) {
    return(ggplot() + theme_void())
  }

  # --- main curves ---
  M <- as_curve_matrix(locations, f, prefix = "curve")
  data_long <- to_long(locations, M)

  plot <- ggplot(data_long, aes(x = x, y = y, group = curve)) +
    geom_point(size = size, color = "black") +
    geom_line(color = "black", linewidth = 0.5)  # connect dots with segments

  # --- true curve ---
  if (!is.null(true)) {
    Tm <- as_curve_matrix(locations, true, prefix = "true")
    data_true <- to_long(locations, Tm)

    if (ncol(M) > 1) {
      # multiple curves → green dashed
      plot <- plot + geom_line(
        data = data_true,
        aes(x = x, y = y),
        color = "green",
        linetype = "dashed",
        linewidth = 1
      )
    } else {
      # single curve → black dotted
      plot <- plot + geom_line(
        data = data_true,
        aes(x = x, y = y),
        color = "black",
        linetype = "dotted",
        linewidth = 0.8
      )
    }
  }

  # --- y limits ---
  if (!is.null(limits)) {
    plot <- plot + ylim(limits[1], limits[2])
  }

  # --- remove legend ---
  plot <- plot + theme(legend.position = "none")

  return(plot)
}

## Function: plot.field_points
# - Args:
#   * locations: matrix or data.frame with 2 columns (x, y) for coordinates
#   * f: numeric vector of values to be plotted
#   * boundary: optional SpatialPolygons or data.frame defining a boundary
#   * size: numeric, point size
#   * limits: optional numeric range for color scaling
#   * colormap: string, Viridis palette option (default "D")
#   * discrete: logical, whether to use discrete colormap
#   * LEGEND: logical, whether to display the legend
# - Desc:
#   Plots a spatial field defined at scattered locations using colored points.
#   Supports both continuous and discrete color scales, with optional boundary overlay.
plot.field_points <- function(locations, f, boundary = NULL,
                              size = 1, limits = NULL, colormap = "D",
                              discrete = FALSE, LEGEND = FALSE) {

  ## Handle null input
  if (is.null(f)) {
    return(ggplot() + theme_void())
  }

  ## Assemble data
  data <- data.frame(locations, value = f)
  colnames(data) <- c("x", "y", "value")

  ## Build base plot
  plot <- ggplot() +
    geom_point(data = data, aes(x = x, y = y, color = value), size = size) +
    coord_fixed()

  ## Apply color scale
  if (!discrete) {
    if (is.null(limits)) {
      plot <- plot + scale_color_viridis(option = colormap)
    } else {
      plot <- plot + scale_color_viridis(option = colormap, limits = limits)
    }
  } else {
    plot <- plot + scale_color_viridis_d(option = colormap)
  }

  ## Add boundary if provided
  if (!is.null(boundary)) {
    plot <- plot +
      geom_polygon(data = fortify(boundary), aes(x = long, y = lat),
                   fill = "transparent", color = "black", linewidth = 1)
  }

  ## Add or remove legend
  if (!LEGEND) {
    plot <- plot + guides(color = "none")
  }

  return(plot)
}


## Function: plot.field_tile
# - Args:
#   * nodes: matrix or data.frame with 2 columns (x, y) for coordinates
#   * f: numeric vector of field values
#   * boundary: optional boundary polygon
#   * limits: optional numeric range for color scaling
#   * breaks: optional numeric vector for contour levels
#   * colormap: string, Viridis palette option
#   * palette: optional colour vector, palette list, or ParaView palette name
#   * discrete: logical, whether to use discrete colormap
#   * ISOLINES: logical, whether to draw contour isolines
#   * LEGEND: logical, whether to display the legend
# - Desc:
#   Plots a spatial field on a regular grid using colored tiles.
#   Supports contour overlays, color limits, and boundary visualization.
plot.field_tile <- function(nodes, f, boundary = NULL,
                            limits = NULL, breaks = NULL, colormap = "D",
                            palette = NULL, discrete = FALSE,
                            ISOLINES = FALSE, LEGEND = FALSE) {

  ## Handle null input
  if (is.null(f)) {
    return(ggplot() + theme_void())
  }

  ## Assemble data
  data <- data.frame(nodes, value = f)
  colnames(data) <- c("x", "y", "value")
  data <- na.omit(data)

  ## Build base plot
  plot <- ggplot() +
    geom_tile(data = data, aes(x = x, y = y, fill = value)) +
    coord_fixed()

  ## Add contour isolines if requested
  if (!is.null(breaks) || ISOLINES) {
    color <- "black"
    limits_real <- range(data$value)
    if (is.null(breaks)) {
      breaks <- seq(limits_real[1], limits_real[2], length = 10)
    }
    breaks_initial <- breaks
    h <- breaks[2] - breaks[1]
    if (limits_real[1] < min(breaks)) {
      breaks <- c(sort(seq(min(breaks), limits_real[1] - h, by = -h)[-1]), breaks)
    }
    if (limits_real[2] > max(breaks)) {
      breaks <- c(breaks, seq(max(breaks), limits_real[2] + h, by = h)[-1])
    }
    if (length(breaks) > 2 * length(breaks_initial)) {
      breaks <- breaks_initial
      color <- "red"
    }
    plot <- plot +
      geom_contour(data = data, aes(x = x, y = y, z = value),
                   color = color, breaks = breaks)
  }

  ## Apply color scale
  if (!discrete) {
    if (!is.null(breaks)) {
      h <- breaks[2] - breaks[1]
      limits <- limits + c(-h, h)
    }
    palette <- as_ggplot_palette(palette)
    if (!is.null(palette)) {
      plot <- plot + scale_fill_gradientn(
        colours = palette$colours,
        values = palette$values,
        limits = limits
      )
    } else if (is.null(limits)) {
      plot <- plot + scale_fill_viridis(option = colormap)
    } else {
      plot <- plot + scale_fill_viridis(option = colormap, limits = limits)
    }
  } else {
    plot <- plot + scale_fill_viridis_d(option = colormap)
  }

  ## Add boundary if provided
  if (!is.null(boundary)) {
    plot <- plot +
      geom_polygon(data = fortify(boundary), aes(x = long, y = lat),
                   fill = "transparent", color = "black", linewidth = 1)
  }

  ## Add or remove legend
  if (!LEGEND) {
    plot <- plot + guides(fill = "none")
  }

  return(plot)
}


## Function: plot.grouped_boxplots
# - Args:
#   * data: data.frame with columns Group | Model1 | ... | ModelN
#   * group_name: string, label for the x-axis
#   * subgroup_name: string, label for legend entries
#   * subgroup_colors: optional named vector of colors for subgroups
#   * values_name: string, label for y-axis
#   * limits: optional y-axis range
#   * DIVIDERS: logical, whether to draw vertical separators between groups
#   * LEGEND: logical, whether to display the legend
# - Desc:
#   Creates grouped boxplots comparing models (columns) within multiple groups.
plot.grouped_boxplots <- function(data,
                                  group_name = "Components", group_labels = NULL,
                                  subgroup_name = "Models", subgroup_labels = NULL, subgroup_colors = NULL,
                                  values_name = "Score", limits = NULL,
                                  DIVIDERS = TRUE, LEGEND = TRUE) {

  ## Data integrity check
  if (!("Group" %in% names(data))) stop("The dataframe must contain a column named 'Group'")

  ## Reshape data
  data <- data %>%
    pivot_longer(cols = -Group, names_to = "SubGroup", values_to = "Score")

  ## Extract labels
  groups_levels <- unique(data$Group)
  subgroup_levels <- unique(data$SubGroup)
  if (is.null(group_labels)) group_labels <- groups_levels
  if (is.null(subgroup_labels)) subgroup_labels <- subgroup_levels

  ## Assign colors
  if (is.null(subgroup_colors)) subgroup_colors <- rainbow(length(subgroup_labels))
  names(subgroup_colors) <- subgroup_labels

  ## Refactor categorical variables
  data <- data %>%
    mutate(Group = factor(Group, levels = groups_levels, labels = group_labels)) %>%
    mutate(SubGroup = factor(SubGroup, levels = subgroup_levels, labels = subgroup_labels))

  ## Build plot
  plot <- ggplot(data, aes(x = Group, y = Score, fill = SubGroup, color = SubGroup)) +
    geom_boxplot(na.rm = TRUE) +
    labs(x = group_name, y = values_name) +
    scale_fill_manual(name = subgroup_name, values = subgroup_colors) +
    scale_color_manual(name = subgroup_name, values = subgroup_colors)

  ## Add limits
  if (!is.null(limits)) {
    plot <- plot + scale_y_continuous(limits = limits)
  }

  ## Add dividers
  if (DIVIDERS && length(group_labels) > 1) {
    plot <- plot +
      geom_vline(xintercept = seq(1.5, length(unique(group_labels)) - 0.5, 1),
                 lwd = 0.2, colour = "grey")
  }

  ## Add or remove legend
  if (!LEGEND) {
    plot <- plot + guides(fill = "none", color = "none")
  }

  return(plot)
}


## Function: plot.multiple_lines
# - Args:
#   * data: data.frame with columns x | y1 | ... | yN
#   * x_name: string, label for x-axis
#   * subgroup_name: string, label for legend
#   * subgroup_labels, subgroup_colors: optional aesthetics
#   * limits: optional y-axis range
#   * LOGX, LOGY, LOGLOG: logical flags for logarithmic scales
#   * NORMALIZED: logical, normalize curves by their first value
#   * LEGEND: logical, whether to display the legend
# - Desc:
#   Plots multiple lines (e.g., performance curves) on the same axes with
#   optional logarithmic and normalized scaling.
plot.multiple_lines <- function(data,
                                x_name = "Components",
                                x_breaks = NULL,
                                subgroup_name = "Models", subgroup_labels = NULL, subgroup_colors = NULL,
                                values_name = "Score", limits = NULL,
                                LOGX = FALSE, LOGY = FALSE, LOGLOG = FALSE,
                                NORMALIZED = FALSE, LEGEND = TRUE) {

  ## Rename first column
  columns_names <- colnames(data)
  columns_names[1] <- "x"
  colnames(data) <- columns_names

  ## Normalize if requested
  if (NORMALIZED) {
    for (name in columns_names[-1])
      data[, name] <- data[, name] / min(data[, name])
  }

  ## Log-log consistency
  if (LOGLOG) {
    LOGX <- TRUE
    LOGY <- TRUE
  }

  ## Auto-generate breaks if requested
  if (is.logical(x_breaks) && x_breaks) x_breaks <- unique(data$x)

  ## Reshape data
  data <- data %>%
    pivot_longer(cols = -x, names_to = "SubGroup", values_to = "Score")

  ## Extract labels
  subgroup_levels <- unique(data$SubGroup)
  if (is.null(subgroup_labels)) subgroup_labels <- subgroup_levels

  ## Assign colors
  if (is.null(subgroup_colors)) subgroup_colors <- rainbow(length(subgroup_labels))
  names(subgroup_colors) <- subgroup_labels

  ## Refactor categories
  data <- data %>%
    mutate(SubGroup = factor(SubGroup, levels = subgroup_levels, labels = subgroup_labels))

  ## Build plot
  has_lines <- all(tapply(data$x, data$SubGroup, function(x) length(unique(x)) > 1))
  plot <- ggplot(data, aes(x = x, y = Score, color = SubGroup)) +
    labs(x = x_name, y = values_name) +
    scale_color_manual(name = subgroup_name, values = subgroup_colors)
  if (has_lines) {
    plot <- plot + geom_line(linewidth = 1)
  } else {
    plot <- plot + geom_point(size = 2)
  }

  ## Logarithmic reference lines for normalized log-log plots
  if (LOGLOG && NORMALIZED && length(unique(data$x)) > 1) {
    x <- seq(min(data$x), max(data$x), length = 10)
    plot <- plot +
      geom_line(data = data.frame(x = x, y = x / x[1]), aes(x = x, y = y),
                linetype = "dashed", color = "grey", linewidth = 0.3) +
      geom_line(data = data.frame(x = x, y = (x / x[1])^2), aes(x = x, y = y),
                linetype = "dashed", color = "grey", linewidth = 0.3) +
      geom_line(data = data.frame(x = x, y = (x / x[1])^3), aes(x = x, y = y),
                linetype = "dashed", color = "grey", linewidth = 0.3)
  }

  ## Axis scaling
  if (LOGX) {
    plot <- plot + scale_x_log10(breaks = x_breaks)
  } else {
    plot <- plot + scale_x_continuous(breaks = x_breaks)
  }
  if (LOGY) {
    plot <- plot + scale_y_log10(limits = limits)
  } else if (!is.null(limits)) {
    plot <- plot + scale_y_continuous(limits = limits)
  }

  ## Add or remove legend
  if (!LEGEND) {
    plot <- plot + guides(color = "none")
  }

  return(plot)
}


## Function: labled_plots_grid
# - Args:
#   * plot: ggplot or grid object
#   * title: optional string title
#   * labels_cols, labels_rows: optional lists of strings labeling rows/cols
#   * height, width: numeric dimensions
# - Desc:
#   Adds row and column labels (and optional title) to a grid of ggplots.
labled_plots_grid <- function(plot, title = NULL, labels_cols = NULL,
                              labels_rows = NULL, height = 4, width = 4) {

  ## Compute grid dimensions
  n_row <- max(plot$layout$t)
  n_col <- max(plot$layout$l)

  ## Add column labels
  if (!is.null(labels_cols)) {
    labels_grobs_cols <- lapply(labels_cols, function(lab)
      textGrob(lab, gp = gpar(fontsize = 12, fontface = "bold")))
    labels_grobs_cols <- arrangeGrob(grobs = labels_grobs_cols, nrow = 1)
  }

  ## Add row labels
  add <- 0
  if (!is.null(labels_rows)) {
    labels_grobs_rows <- list()
    if (!is.null(labels_cols)) {
      add <- 1
      labels_grobs_rows[[1]] <- textGrob(" ", gp = gpar(fontsize = 12, fontface = "bold"))
    }
    for (row in 1:length(labels_rows) + add) {
      label_row <- labels_rows[[row - add]]
      labels_grobs_rows[[row]] <- textGrob(label_row, gp = gpar(fontsize = 12, fontface = "bold"), rot = 90)
    }
    labels_grobs_rows <- arrangeGrob(grobs = labels_grobs_rows, ncol = 1, heights = c(1, rep(height, n_row)))
  }

  ## Add title
  if (!is.null(title)) {
    title_grob <- textGrob(title, gp = gpar(fontsize = 14, fontface = "bold"))
  }

  ## Combine all components
  if (!is.null(labels_cols)) plot <- arrangeGrob(labels_grobs_cols, plot, heights = c(1, height * n_row))
  if (!is.null(labels_rows)) plot <- arrangeGrob(labels_grobs_rows, plot, widths = c(1, width * n_col))
  if (!is.null(title)) plot <- arrangeGrob(title_grob, plot, heights = c(1, add + height * n_row))

  return(plot)
}


## Function: plot.grouped_violins
# - Args:
#   * data: data.frame with columns Group | Model1 | ... | ModelN
#   * group_name, subgroup_name: strings, axis and legend labels
#   * subgroup_colors: optional colors for subgroups
#   * values_name: string, y-axis label
#   * limits: optional numeric y-axis range
#   * DIVIDERS, LEGEND: logical flags
#   * show_boxplot: logical, overlay boxplots inside violins
# - Desc:
#   Draws grouped violin plots comparing model distributions across groups,
#   with optional embedded boxplots and group separators.
plot.grouped_violins <- function(data,
                                 group_name = "Components", group_labels = NULL,
                                 subgroup_name = "Models", subgroup_labels = NULL, subgroup_colors = NULL,
                                 values_name = "Score", limits = NULL,
                                 DIVIDERS = TRUE, LEGEND = TRUE, show_boxplot = TRUE) {

  ## Data integrity check
  if (!("Group" %in% names(data))) stop("The dataframe must contain a column named 'Group'")

  ## Reshape data
  data <- data %>%
    pivot_longer(cols = -Group, names_to = "SubGroup", values_to = "Score")

  ## Extract labels
  groups_levels <- unique(data$Group)
  subgroup_levels <- unique(data$SubGroup)
  if (is.null(group_labels)) group_labels <- groups_levels
  if (is.null(subgroup_labels)) subgroup_labels <- subgroup_levels

  ## Assign colors
  if (is.null(subgroup_colors)) subgroup_colors <- rainbow(length(subgroup_labels))
  names(subgroup_colors) <- subgroup_labels

  ## Refactor variables
  data <- data %>%
    mutate(Group = factor(Group, levels = groups_levels, labels = group_labels)) %>%
    mutate(SubGroup = factor(SubGroup, levels = subgroup_levels, labels = subgroup_labels))

  ## Build violin plot
  plot <- ggplot(data, aes(x = Group, y = Score, fill = SubGroup)) +
    geom_violin(trim = FALSE, width = 1.5, position = position_dodge(width = 0.8),
                na.rm = TRUE, alpha = 0.8) +
    labs(x = group_name, y = values_name) +
    scale_fill_manual(name = subgroup_name, values = subgroup_colors)

  ## Optionally overlay boxplots
  if (show_boxplot) {
    plot <- plot +
      geom_boxplot(width = 0.15, position = position_dodge(width = 0.8),
                   outlier.shape = NA, alpha = 0.6)
  }

  ## Apply y-limits
  if (!is.null(limits)) {
    plot <- plot + scale_y_continuous(
      limits = limits
    )
  }

  ## Add groups divider if required
  if (DIVIDERS) {
    if (length(group_labels) > 1) {
      plot <- plot +
        geom_vline(
          xintercept = seq(1.5, length(unique(group_labels)) - 0.5, 1),
          lwd = 0.2, colour = "grey"
        )
    }
  }

  ## Legend control
  if (!LEGEND) {
    plot <- plot + guides(fill = "none")
  }

  return(plot)
}



# = ========================================================================== =
# - Script: aggregated_plots.R
# - Author: Pietro Donelli
# - Date: 2025-10-24
# - Desc: Aggregates quantitative results across varying options and produces
#         comparative plots (boxplots, lines, log-x, log-log, normalized).
#         Supports multi-dimensional option grids with labeled faceting.
# = ========================================================================== =


## Function: plot.aggregated_data
# - Args:
#   * loaded_results: list carrying model metadata and (optionally) varying_options
#       - $model_names, $model_labels, $model_colors
#       - $varying_options: character vector of option names used for grouping
#   * data_plot_orig: data.frame with columns:
#       - "Group" (aggregation variable = first varying option)
#       - one column per model in loaded_results$model_names
#       - one column per varying option (added upstream)
#   * title_prefix: string prefix for figure titles
#   * values_names: y-axis label passed to the plotting helpers
#   * order: optional integer vector to reorder varying_options (default: 1:k)
#   * limits: optional y-axis limits c(ymin, ymax) for value scales
#   * plots_catalog: list of toggles {boxplots, lines, logx, loglog, normalized}
# - Desc:
#   Builds per-group panels of aggregated results over the first varying option,
#   conditioning on all remaining varying options. For each combination, it can
#   render boxplots and/or line plots (linear, log-x, log-log, normalized).
plot.aggregated_data <- function(loaded_results, data_plot_orig, title_prefix, values_names, order = NULL, limits = NULL, plots_catalog = NULL) {

  ## Get model-related properties
  model_names  <- loaded_results$model_names
  model_labels <- loaded_results$model_labels
  model_colors <- loaded_results$model_colors

  ## Get varying options and apply ordering
  varying_options <- loaded_results$varying_options
  if (is.null(order)) order <- seq_along(varying_options)
  varying_options <- varying_options[order]
  name_varying_options <- varying_options

  ## Build options grid (unique sorted values for each varying option)
  options_grid <- list()
  for (name_ao in varying_options) {
    options_grid[[name_ao]] <- unique(data_plot_orig[, name_ao])
    options_grid[[name_ao]] <- sort(options_grid[[name_ao]])
  }

  ## Plots catalog defaults
  if (is.null(plots_catalog)) {
    plots_catalog <- list(
      boxplots = TRUE,
      lines = FALSE,
      logx = FALSE,
      loglog = FALSE,
      normalized = FALSE
    )
  }

  ## Detect groups (values of the first varying option will become x-axis)
  groups <- sort(unique(data_plot_orig$Group))

  page_started <- FALSE
  draw_plot_page <- function(plot_grob) {
    if (page_started) grid::grid.newpage()
    grid::grid.draw(plot_grob)
    page_started <<- TRUE
  }

  ## If there is more than one group, plot them sequentially
  for (group in groups) {  # group <- groups[1]

    ## Select the specific group
    data_plot <- data_plot_orig[data_plot_orig$Group == group, ]

    ## Generate title
    group_suffix <- if (length(groups) > 1) glue::glue("- {group}") else ""
    title <- trimws(glue::glue(
      "{title_prefix} {name_varying_options[1]} {group_suffix}"
    ))

    ## Rooms for plots
    boxplot_list <- list()
    plot_list <- list()
    plot_logx_list <- list()
    plot_loglog_list <- list()
    plot_loglog_normalized_list <- list()

    name_aggregation_option <- varying_options[1]
    group_name <- name_varying_options[1]

    options_grid_selected <- options_grid
    options_grid_selected[[name_aggregation_option]] <- NULL
    names_options_selected  <- names(options_grid_selected)
    labels_options_selected <- name_varying_options[-1]

    ## Handle 1D case (only one varying option)
    if (length(options_grid_selected) == 0) {
      combinations_options <- data.frame(dummy = 1)
      labels_rows <- ""
      labels_cols <- ""
    } else {
      mg <- do.call(expand.grid, options_grid_selected)
      combinations_options <- do.call(data.frame, lapply(mg, as.vector))
      colnames(combinations_options) <- names_options_selected

      labels_rows <- if (length(labels_options_selected) >= 1) {
        glue::glue("{labels_options_selected[1]} = {options_grid_selected[[1]]}")
      } else ""
      labels_cols <- if (length(labels_options_selected) >= 2) {
        glue::glue("{labels_options_selected[2]} = {options_grid_selected[[2]]}")
      } else ""
    }

    for (j in 1:nrow(combinations_options)) {  # j <- 1

      ## Data preparation
      if (length(names_options_selected) == 0) {
        ## 1D case: use all data
        data_plot_trimmed <- data_plot[, c(name_aggregation_option, model_names)]
      } else {
        ## ND case: filter by combination
        condition <- rep(TRUE, nrow(data_plot))
        for (k in seq_along(names_options_selected)) {
          condition <- condition & (data_plot[[names_options_selected[k]]] == combinations_options[j, k])
        }
        data_plot_trimmed <- data_plot[condition, c(name_aggregation_option, model_names)]
      }
      colnames(data_plot_trimmed)[1] <- "Group"
      data_plot_trimmed <- data_plot_trimmed[order(data_plot_trimmed$Group), ]

      ## Skip if data is empty
      if (nrow(data_plot_trimmed) == 0) next

      ## Remove models with all-NaN results
      valid_models <- model_names[!apply(data_plot_trimmed[, model_names], 2, function(x) all(is.nan(x)))]
      if (length(valid_models) == 0) next

      ## Aggregate with median per x (Group)
      data_plot_aggregated <- aggregate(. ~ Group, data = data_plot_trimmed[, c("Group", valid_models)], FUN = median)

      ## Boxplots
      if (isTRUE(plots_catalog$boxplots)) {
        boxplot_list[[j]] <- plot.grouped_boxplots(
          data_plot_trimmed[, c("Group", valid_models)],
          values_name = values_names,
          group_name = group_name,
          subgroup_name = "Approaches",
          subgroup_labels = model_labels[match(valid_models, model_names)],
          subgroup_colors = model_colors[match(valid_models, model_names)],
          limits = limits,
          LEGEND = FALSE
        ) + std_plot_settings()
      }

      ## Lines (linear x)
      if (isTRUE(plots_catalog$lines)) {
        plot_list[[j]] <- plot.multiple_lines(
          data_plot_aggregated[, c("Group", valid_models)],
          values_name = values_names,
          x_name = group_name,
          x_breaks = TRUE,
          subgroup_name = "Approaches",
          subgroup_labels = model_labels[match(valid_models, model_names)],
          subgroup_colors = model_colors[match(valid_models, model_names)],
          LEGEND = FALSE,
          limits  = limits,
          NORMALIZED = FALSE,
          LOGX = FALSE
        ) + std_plot_settings()
      }

      ## Lines (log-x)
      if (isTRUE(plots_catalog$logx)) {
        plot_logx_list[[j]] <- plot.multiple_lines(
          data_plot_aggregated[, c("Group", valid_models)],
          values_name = values_names,
          x_name = group_name,
          x_breaks = TRUE,
          subgroup_name = "Approaches",
          subgroup_labels = model_labels[match(valid_models, model_names)],
          subgroup_colors = model_colors[match(valid_models, model_names)],
          LEGEND = FALSE,
          limits = limits,
          NORMALIZED = FALSE,
          LOGX = TRUE
        ) + std_plot_settings()
      }

      ## Lines (log-log)
      if (isTRUE(plots_catalog$loglog)) {
        plot_loglog_list[[j]] <- plot.multiple_lines(
          data_plot_aggregated[, c("Group", valid_models)],
          values_name = values_names,
          x_name = group_name,
          x_breaks = TRUE,
          subgroup_name = "Approaches",
          subgroup_labels = model_labels[match(valid_models, model_names)],
          subgroup_colors = model_colors[match(valid_models, model_names)],
          LEGEND = FALSE,
          limits = NULL,
          NORMALIZED = FALSE,
          LOGLOG = TRUE
        ) + std_plot_settings()
      }

      ## Lines (log-log, normalized)
      if (isTRUE(plots_catalog$normalized)) {
        plot_loglog_normalized_list[[j]] <- plot.multiple_lines(
          data_plot_aggregated[, c("Group", valid_models)],
          values_name = values_names,
          x_name = group_name,
          x_breaks = TRUE,
          subgroup_name = "Approaches",
          subgroup_labels = model_labels[match(valid_models, model_names)],
          subgroup_colors = model_colors[match(valid_models, model_names)],
          LEGEND = FALSE,
          limits = NULL,
          NORMALIZED = TRUE,
          LOGLOG = TRUE
        ) + std_plot_settings()
      }
    }

    ## Handle layout safely if 1D: use 1 column
    ncols <- if (length(labels_cols) == 0) 1 else length(labels_cols)

    if (isTRUE(plots_catalog$boxplots)) {
      boxplot <- arrangeGrob(grobs = boxplot_list, ncol = ncols, as.table = FALSE)
      boxplot <- labled_plots_grid(boxplot, title, labels_cols, labels_rows, 9, 7)
      draw_plot_page(boxplot)
    }

    if (isTRUE(plots_catalog$lines)) {
      plot <- arrangeGrob(grobs = plot_list, ncol = ncols, as.table = FALSE)
      plot <- labled_plots_grid(plot, title, labels_cols, labels_rows, 9, 7)
      draw_plot_page(plot)
    }

    if (isTRUE(plots_catalog$logx)) {
      plot_logx <- arrangeGrob(grobs = plot_logx_list, ncol = ncols, as.table = FALSE)
      plot_logx <- labled_plots_grid(plot_logx, title, labels_cols, labels_rows, 9, 7)
      draw_plot_page(plot_logx)
    }

    if (isTRUE(plots_catalog$loglog)) {
      plot_loglog <- arrangeGrob(grobs = plot_loglog_list, ncol = ncols, as.table = FALSE)
      plot_loglog <- labled_plots_grid(plot_loglog, title, labels_cols, labels_rows, 9, 7)
      draw_plot_page(plot_loglog)
    }

    if (isTRUE(plots_catalog$normalized)) {
      plot_loglog_normalized <- arrangeGrob(grobs = plot_loglog_normalized_list, ncol = ncols, as.table = FALSE)
      plot_loglog_normalized <- labled_plots_grid(plot_loglog_normalized, title, labels_cols, labels_rows, 9, 7)
      draw_plot_page(plot_loglog_normalized)
    }
  }
}
