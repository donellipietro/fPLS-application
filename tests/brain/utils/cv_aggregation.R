# = ========================================================================== =
# - Script: cv_aggregation.R
# - Desc: Repeated-CV performance and loading reproducibility summaries.
# = ========================================================================== =

bind_cv_field <- function(evaluations, field) {
  do.call(rbind, lapply(evaluations, function(value) {
    data <- value[[field]]
    if (is.null(data)) return(NULL)
    cbind(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      data
    )
  }))
}

oof_metrics_by_repeat <- function(predictions) {
  groups <- split(
    predictions,
    interaction(predictions$repeat_index, predictions$method, predictions$retained_components, drop = TRUE)
  )
  do.call(rbind, lapply(groups, function(value) {
    metrics <- classification_metrics(
      value$actual,
      value$classification_margin,
      predicted = value$predicted
    )
    cbind(
      repeat_index = value$repeat_index[1],
      method = value$method[1],
      retained_components = value$retained_components[1],
      metrics
    )
  }))
}

summarize_repeated_metrics <- function(metrics) {
  metric_names <- c(
    "accuracy", "sensitivity_schz", "specificity_ctrl", "balanced_accuracy",
    "roc_auc_schz", "average_precision_schz", "mcc"
  )
  long <- do.call(rbind, lapply(metric_names, function(metric) {
    data.frame(
      repeat_index = metrics$repeat_index,
      method = metrics$method,
      retained_components = metrics$retained_components,
      metric = metric,
      value = metrics[[metric]]
    )
  }))
  groups <- split(long, interaction(long$method, long$retained_components, long$metric, drop = TRUE))
  summary <- do.call(rbind, lapply(groups, function(value) {
    data.frame(
      method = value$method[1],
      retained_components = value$retained_components[1],
      metric = value$metric[1],
      mean = mean(value$value),
      sd = sd(value$value),
      median = median(value$value),
      q025 = unname(quantile(value$value, 0.025)),
      q975 = unname(quantile(value$value, 0.975)),
      repeats = nrow(value)
    )
  }))
  list(values = long, summary = summary)
}

cv_loading_stability <- function(evaluations, points, elements) {
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  metadata <- do.call(rbind, lapply(seq_along(evaluations), function(index) {
    value <- evaluations[[index]]
    data.frame(
      evaluation_index = index,
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index
    )
  }))

  comparisons <- list()
  row <- 0L
  for (repeat_index in sort(unique(metadata$repeat_index))) {
    repeat_rows <- metadata[metadata$repeat_index == repeat_index, , drop = FALSE]
    pairs <- combn(seq_len(nrow(repeat_rows)), 2L)
    example <- evaluations[[repeat_rows$evaluation_index[1]]]
    for (quantity in names(example$loading_maps)) {
      for (h in sort(as.integer(names(example$loading_maps[[quantity]])))) {
        for (pair_index in seq_len(ncol(pairs))) {
          left <- repeat_rows[pairs[1, pair_index], ]
          right <- repeat_rows[pairs[2, pair_index], ]
          left_map <- matrix(
            evaluations[[left$evaluation_index]]$loading_maps[[quantity]][[as.character(h)]],
            ncol = 1L
          )
          right_map <- matrix(
            evaluations[[right$evaluation_index]]$loading_maps[[quantity]][[as.character(h)]],
            ncol = 1L
          )
          row <- row + 1L
          comparison <- mass_stability(left_map, right_map, elements, volumes, sign_align = FALSE)
          comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
          comparisons[[row]] <- cbind(
            repeat_index = repeat_index,
            retained_components = h,
            quantity = quantity,
            fold_left = left$fold_index,
            fold_right = right$fold_index,
            comparison
          )
        }
      }
    }
  }
  pairwise <- do.call(rbind, comparisons)
  repeat_groups <- split(
    pairwise,
    interaction(pairwise$repeat_index, pairwise$quantity, pairwise$retained_components, drop = TRUE)
  )
  by_repeat <- do.call(rbind, lapply(repeat_groups, function(value) {
    data.frame(
      repeat_index = value$repeat_index[1],
      quantity = value$quantity[1],
      retained_components = value$retained_components[1],
      mean_mass_correlation = mean(value$mass_correlation),
      minimum_mass_correlation = min(value$mass_correlation),
      mean_unit_mass_distance = mean(value$unit_mass_distance),
      fold_pairs = nrow(value)
    )
  }))
  summary_groups <- split(
    by_repeat,
    interaction(by_repeat$quantity, by_repeat$retained_components, drop = TRUE)
  )
  summary <- do.call(rbind, lapply(summary_groups, function(value) {
    data.frame(
      quantity = value$quantity[1],
      retained_components = value$retained_components[1],
      mean_mass_correlation = mean(value$mean_mass_correlation),
      sd_mass_correlation = sd(value$mean_mass_correlation),
      mean_minimum_mass_correlation = mean(value$minimum_mass_correlation),
      mean_unit_mass_distance = mean(value$mean_unit_mass_distance),
      repeats = nrow(value)
    )
  }))
  list(pairwise = pairwise, by_repeat = by_repeat, summary = summary)
}

slider_components <- function(evaluations) {
  Reduce(intersect, lapply(evaluations, function(value) {
    as.integer(names(value$loading_maps[["SVM slider loading"]]))
  }))
}

slider_map <- function(evaluation, h) {
  matrix(evaluation$loading_maps[["SVM slider loading"]][[as.character(h)]], ncol = 1L)
}

summarize_slider_comparisons <- function(comparisons, group_column = "retained_components") {
  if (is.null(comparisons) || nrow(comparisons) == 0L) return(data.frame())
  groups <- split(comparisons, comparisons[[group_column]])
  do.call(rbind, lapply(groups, function(value) {
    data.frame(
      retained_components = value$retained_components[1],
      mean_mass_correlation = mean(value$mass_correlation),
      sd_mass_correlation = sd(value$mass_correlation),
      minimum_mass_correlation = min(value$mass_correlation),
      mean_unit_mass_distance = mean(value$unit_mass_distance),
      comparisons = nrow(value)
    )
  }))
}

cv_slider_cross_h_stability <- function(evaluations, points, elements, reference_h = 3L) {
  components <- slider_components(evaluations)
  targets <- components[components > reference_h]
  if (!(reference_h %in% components) || length(targets) == 0L) {
    return(list(comparisons = data.frame(), summary = data.frame()))
  }
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  comparisons <- do.call(rbind, lapply(seq_along(evaluations), function(index) {
    evaluation <- evaluations[[index]]
    reference <- slider_map(evaluation, reference_h)
    do.call(rbind, lapply(targets, function(h) {
      comparison <- mass_stability(reference, slider_map(evaluation, h), elements, volumes, sign_align = FALSE)
      comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
      cbind(
        repeat_index = evaluation$cross_validation$repeat_index,
        fold_index = evaluation$cross_validation$fold_index,
        reference_components = reference_h,
        retained_components = h,
        comparison
      )
    }))
  }))
  list(comparisons = comparisons, summary = summarize_slider_comparisons(comparisons))
}

load_complete_data_slider_maps <- function(cfg, components) {
  reference_dir <- file.path(
    cfg$PATH_RESULTS, "brain", "aggregate", "h_stability", "maximum_margin_maps"
  )
  paths <- setNames(
    file.path(reference_dir, paste0("reconstruction_loading_h", components, ".csv")),
    as.character(components)
  )
  available <- paths[file.exists(paths)]
  maps <- lapply(available, function(path) {
    matrix(as.numeric(read.csv(path, check.names = FALSE)[[1]]), ncol = 1L)
  })
  list(
    maps = maps,
    reference_dir = reference_dir,
    missing_components = as.integer(names(paths)[!file.exists(paths)])
  )
}

cv_slider_vs_complete_data <- function(evaluations, points, elements, complete_maps) {
  components <- intersect(slider_components(evaluations), as.integer(names(complete_maps)))
  if (length(components) == 0L) return(list(comparisons = data.frame(), summary = data.frame()))
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  comparisons <- do.call(rbind, lapply(seq_along(evaluations), function(index) {
    evaluation <- evaluations[[index]]
    do.call(rbind, lapply(components, function(h) {
      comparison <- mass_stability(
        complete_maps[[as.character(h)]], slider_map(evaluation, h), elements, volumes, sign_align = FALSE
      )
      comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
      cbind(
        repeat_index = evaluation$cross_validation$repeat_index,
        fold_index = evaluation$cross_validation$fold_index,
        retained_components = h,
        comparison
      )
    }))
  }))
  list(comparisons = comparisons, summary = summarize_slider_comparisons(comparisons))
}

cv_slider_consensus_maps <- function(evaluations, points, elements) {
  components <- slider_components(evaluations)
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  maps <- setNames(lapply(components, function(h) {
    unit_maps <- lapply(evaluations, function(evaluation) {
      value <- slider_map(evaluation, h)
      value / sqrt(drop(mass_crossprod(value, value, elements, volumes)))
    })
    consensus <- Reduce(`+`, unit_maps) / length(unit_maps)
    consensus / sqrt(drop(mass_crossprod(consensus, consensus, elements, volumes)))
  }), as.character(components))
  list(maps = maps, fits = length(evaluations))
}

plot_slider_correlation <- function(summary, filename, x_label, y_label) {
  if (nrow(summary) == 0L) return(invisible(NULL))
  plot <- ggplot(summary, aes(retained_components, mean_mass_correlation)) +
    geom_errorbar(
      aes(ymin = mean_mass_correlation - sd_mass_correlation, ymax = mean_mass_correlation + sd_mass_correlation),
      width = 0.12,
      na.rm = TRUE
    ) +
    geom_point(size = 2, colour = "#007C91") +
    scale_x_continuous(breaks = sort(unique(summary$retained_components))) +
    coord_cartesian(ylim = c(-1, 1)) +
    labs(x = x_label, y = y_label) +
    theme_bw()
  if (nrow(summary) > 1L) plot <- plot + geom_line(linewidth = 0.7, colour = "#007C91")
  ggsave(filename, plot, width = 7, height = 4.5, dpi = 180)
}

aggregate_cv_results <- function(evaluations, aggregate_dir, image_dir, cfg) {
  fold_metrics <- bind_cv_field(evaluations, "fold_metrics")
  predictions <- bind_cv_field(evaluations, "predictions")
  tuning <- bind_cv_field(evaluations, "svm_tuning")
  lambdas <- do.call(rbind, lapply(evaluations, function(value) {
    data.frame(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      component = seq_along(value$direction_lambda),
      direction_lambda = value$direction_lambda,
      loading_lambda = value$loading_lambda
    )
  }))
  resources <- do.call(rbind, lapply(evaluations, function(value) {
    data.frame(
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      wall_seconds = as.numeric(value$execution_time),
      peak_ram_mib = value$peak_ram_mib,
      projection_max_abs_error = value$projection_max_abs_error
    )
  }))
  oof_metrics <- oof_metrics_by_repeat(predictions)
  performance <- summarize_repeated_metrics(oof_metrics)
  mesh <- load_brain_mesh(cfg$PATH_APPLICATION_DATA)
  stability <- cv_loading_stability(evaluations, mesh$nodes, mesh$elements)
  cross_h <- cv_slider_cross_h_stability(evaluations, mesh$nodes, mesh$elements)
  complete_data <- load_complete_data_slider_maps(cfg, slider_components(evaluations))
  against_complete <- cv_slider_vs_complete_data(
    evaluations, mesh$nodes, mesh$elements, complete_data$maps
  )
  consensus <- cv_slider_consensus_maps(evaluations, mesh$nodes, mesh$elements)

  write.csv(fold_metrics, file.path(aggregate_dir, "cv_fold_metrics.csv"), row.names = FALSE)
  write.csv(predictions, file.path(aggregate_dir, "cv_predictions.csv"), row.names = FALSE)
  write.csv(tuning, file.path(aggregate_dir, "cv_svm_tuning.csv"), row.names = FALSE)
  write.csv(lambdas, file.path(aggregate_dir, "cv_selected_lambdas.csv"), row.names = FALSE)
  write.csv(resources, file.path(aggregate_dir, "cv_resources.csv"), row.names = FALSE)
  write.csv(oof_metrics, file.path(aggregate_dir, "cv_oof_metrics_by_repeat.csv"), row.names = FALSE)
  write.csv(performance$summary, file.path(aggregate_dir, "cv_performance_summary.csv"), row.names = FALSE)
  write.csv(stability$pairwise, file.path(aggregate_dir, "cv_loading_pairwise_stability.csv"), row.names = FALSE)
  write.csv(stability$by_repeat, file.path(aggregate_dir, "cv_loading_stability_by_repeat.csv"), row.names = FALSE)
  write.csv(stability$summary, file.path(aggregate_dir, "cv_loading_stability_summary.csv"), row.names = FALSE)
  if (nrow(cross_h$comparisons) > 0L) {
    write.csv(cross_h$comparisons, file.path(aggregate_dir, "cv_slider_cross_H_stability.csv"), row.names = FALSE)
    write.csv(cross_h$summary, file.path(aggregate_dir, "cv_slider_cross_H_stability_summary.csv"), row.names = FALSE)
  }
  if (nrow(against_complete$comparisons) > 0L) {
    write.csv(against_complete$comparisons, file.path(aggregate_dir, "cv_slider_vs_complete_data.csv"), row.names = FALSE)
    write.csv(against_complete$summary, file.path(aggregate_dir, "cv_slider_vs_complete_data_summary.csv"), row.names = FALSE)
  }
  consensus_dir <- file.path(aggregate_dir, "cv_slider_consensus_maps")
  dir.create(consensus_dir, recursive = TRUE, showWarnings = FALSE)
  for (h in names(consensus$maps)) {
    write.csv(
      data.frame(coefficient = drop(consensus$maps[[h]])),
      file.path(consensus_dir, paste0("slider_consensus_h", h, ".csv")),
      row.names = FALSE
    )
  }

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  plotted_metrics <- c("balanced_accuracy", "roc_auc_schz", "average_precision_schz", "mcc")
  plot_data <- performance$summary[performance$summary$metric %in% plotted_metrics, , drop = FALSE]
  performance_plot <- ggplot(plot_data, aes(retained_components, mean, colour = method)) +
    geom_errorbar(aes(ymin = mean - sd, ymax = mean + sd), width = 0.12, na.rm = TRUE) +
    geom_point(size = 2) +
    facet_wrap(~ metric, scales = "free_y") +
    scale_x_continuous(breaks = sort(unique(plot_data$retained_components))) +
    labs(x = "Retained components H", y = "Repeated-CV mean +/- SD", colour = NULL) +
    theme_bw() +
    theme(legend.position = "top")
  if (length(unique(plot_data$retained_components)) > 1L) {
    performance_plot <- performance_plot + geom_line(linewidth = 0.7)
  }
  ggsave(plot_file(image_dir, "cv_out_of_sample_performance"), performance_plot, width = 9, height = 6, dpi = 180)

  stability_plot <- ggplot(
    stability$summary,
    aes(retained_components, mean_mass_correlation, colour = quantity)
  ) +
    geom_errorbar(
      aes(ymin = mean_mass_correlation - sd_mass_correlation, ymax = mean_mass_correlation + sd_mass_correlation),
      width = 0.12,
      na.rm = TRUE
    ) +
    geom_point(size = 2) +
    scale_x_continuous(breaks = sort(unique(stability$summary$retained_components))) +
    coord_cartesian(ylim = c(-1, 1)) +
    labs(x = "Retained components H", y = "Between-training-fit FEM mass correlation", colour = NULL) +
    theme_bw() +
    theme(legend.position = "top")
  if (length(unique(stability$summary$retained_components)) > 1L) {
    stability_plot <- stability_plot + geom_line(linewidth = 0.7)
  }
  ggsave(plot_file(image_dir, "cv_loading_reproducibility"), stability_plot, width = 8, height = 4.8, dpi = 180)
  plot_slider_correlation(
    cross_h$summary,
    plot_file(image_dir, "cv_slider_cross_H_stability"),
    "Retained components H",
    "FEM mass correlation with the H=3 slider map"
  )
  plot_slider_correlation(
    against_complete$summary,
    plot_file(image_dir, "cv_slider_vs_complete_data"),
    "Retained components H",
    "FEM mass correlation with the complete-data slider map"
  )

  list(
    repeats = length(unique(predictions$repeat_index)),
    folds = length(unique(predictions$fold_index)),
    fits = length(evaluations),
    native_components = max(lambdas$component),
    evaluated_components = sort(unique(predictions$retained_components)),
    max_projection_error = max(resources$projection_max_abs_error),
    performance = performance,
    stability = stability,
    slider_cross_h = cross_h,
    slider_against_complete_data = against_complete,
    complete_data_reference = complete_data,
    consensus_slider_maps = consensus
  )
}
