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

  list(
    repeats = length(unique(predictions$repeat_index)),
    folds = length(unique(predictions$fold_index)),
    fits = length(evaluations),
    native_components = max(lambdas$component),
    evaluated_components = sort(unique(predictions$retained_components)),
    max_projection_error = max(resources$projection_max_abs_error),
    performance = performance,
    stability = stability
  )
}
