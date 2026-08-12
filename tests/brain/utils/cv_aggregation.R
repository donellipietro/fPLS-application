# = ========================================================================== =
# - Script: cv_aggregation.R
# - Desc: Repeated-CV performance and loading reproducibility summaries.
# = ========================================================================== =

evaluation_reducer <- function(evaluation) {
  reducer <- evaluation$dimension_reducer
  if (is.null(reducer)) reducer <- evaluation$provenance$model
  if (identical(reducer, "R1_fPLS")) reducer <- "R1-fPLS"
  if (is.null(reducer) || !reducer %in% c("R1-fPLS", "fPCR")) {
    stop("CV evaluation has no recognized dimension reducer")
  }
  reducer
}

reducer_slug <- function(reducer) {
  if (identical(reducer, "R1-fPLS")) "R1_fPLS" else "fPCR"
}

bind_cv_field <- function(evaluations, field) {
  do.call(rbind, lapply(evaluations, function(value) {
    data <- value[[field]]
    if (is.null(data)) return(NULL)
    if (!"dimension_reducer" %in% names(data)) {
      data$dimension_reducer <- evaluation_reducer(value)
    }
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
    interaction(
      predictions$repeat_index,
      predictions$dimension_reducer,
      predictions$classifier,
      predictions$retained_components,
      drop = TRUE
    )
  )
  do.call(rbind, lapply(groups, function(value) {
    metrics <- classification_metrics(
      value$actual,
      value$classification_margin,
      predicted = value$predicted
    )
    cbind(
      repeat_index = value$repeat_index[1],
      dimension_reducer = value$dimension_reducer[1],
      classifier = value$classifier[1],
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
      dimension_reducer = metrics$dimension_reducer,
      classifier = metrics$classifier,
      retained_components = metrics$retained_components,
      metric = metric,
      value = metrics[[metric]]
    )
  }))
  groups <- split(
    long,
    interaction(
      long$dimension_reducer,
      long$classifier,
      long$retained_components,
      long$metric,
      drop = TRUE
    )
  )
  summary <- do.call(rbind, lapply(groups, function(value) {
    data.frame(
      dimension_reducer = value$dimension_reducer[1],
      classifier = value$classifier[1],
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
      dimension_reducer = evaluation_reducer(value),
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index
    )
  }))

  comparisons <- list()
  row <- 0L
  fit_groups <- split(
    metadata,
    interaction(metadata$dimension_reducer, metadata$repeat_index, drop = TRUE)
  )
  for (repeat_rows in fit_groups) {
    if (nrow(repeat_rows) < 2L) next
    pairs <- combn(seq_len(nrow(repeat_rows)), 2L)
    group_evaluations <- evaluations[repeat_rows$evaluation_index]
    quantities <- Reduce(intersect, lapply(group_evaluations, function(value) names(value$loading_maps)))
    for (quantity in quantities) {
      components <- Reduce(intersect, lapply(group_evaluations, function(value) {
        as.integer(names(value$loading_maps[[quantity]]))
      }))
      for (h in sort(components)) {
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
          comparison <- mass_stability(left_map, right_map, elements, volumes, sign_align = FALSE)
          comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
          row <- row + 1L
          comparisons[[row]] <- cbind(
            dimension_reducer = left$dimension_reducer,
            repeat_index = left$repeat_index,
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
  if (length(comparisons) == 0L) {
    return(list(pairwise = data.frame(), by_repeat = data.frame(), summary = data.frame()))
  }

  pairwise <- do.call(rbind, comparisons)
  repeat_groups <- split(
    pairwise,
    interaction(
      pairwise$dimension_reducer,
      pairwise$repeat_index,
      pairwise$quantity,
      pairwise$retained_components,
      drop = TRUE
    )
  )
  by_repeat <- do.call(rbind, lapply(repeat_groups, function(value) {
    data.frame(
      dimension_reducer = value$dimension_reducer[1],
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
    interaction(
      by_repeat$dimension_reducer,
      by_repeat$quantity,
      by_repeat$retained_components,
      drop = TRUE
    )
  )
  summary <- do.call(rbind, lapply(summary_groups, function(value) {
    data.frame(
      dimension_reducer = value$dimension_reducer[1],
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
  if (length(evaluations) == 0L) return(integer())
  Reduce(intersect, lapply(evaluations, function(value) {
    as.integer(names(value$loading_maps[["SVM slider loading"]]))
  }))
}

slider_map <- function(evaluation, h) {
  matrix(evaluation$loading_maps[["SVM slider loading"]][[as.character(h)]], ncol = 1L)
}

summarize_slider_comparisons <- function(comparisons) {
  if (is.null(comparisons) || nrow(comparisons) == 0L) return(data.frame())
  groups <- split(
    comparisons,
    interaction(comparisons$dimension_reducer, comparisons$retained_components, drop = TRUE)
  )
  do.call(rbind, lapply(groups, function(value) {
    data.frame(
      dimension_reducer = value$dimension_reducer[1],
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
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  comparisons <- list()
  row <- 0L
  for (evaluation in evaluations) {
    components <- as.integer(names(evaluation$loading_maps[["SVM slider loading"]]))
    targets <- components[components > reference_h]
    if (!(reference_h %in% components) || length(targets) == 0L) next
    reference <- slider_map(evaluation, reference_h)
    for (h in targets) {
      comparison <- mass_stability(reference, slider_map(evaluation, h), elements, volumes, sign_align = FALSE)
      comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
      row <- row + 1L
      comparisons[[row]] <- cbind(
        dimension_reducer = evaluation_reducer(evaluation),
        repeat_index = evaluation$cross_validation$repeat_index,
        fold_index = evaluation$cross_validation$fold_index,
        reference_components = reference_h,
        retained_components = h,
        comparison
      )
    }
  }
  if (length(comparisons) == 0L) {
    return(list(comparisons = data.frame(), summary = data.frame()))
  }
  comparisons <- do.call(rbind, comparisons)
  list(comparisons = comparisons, summary = summarize_slider_comparisons(comparisons))
}

load_complete_data_slider_maps <- function(cfg, components, dimension_reducer = "R1-fPLS") {
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
    dimension_reducer = dimension_reducer,
    maps = maps,
    reference_dir = reference_dir,
    missing_components = as.integer(names(paths)[!file.exists(paths)])
  )
}

cv_slider_vs_complete_data <- function(evaluations, points, elements, complete_data) {
  evaluations <- Filter(
    function(value) identical(evaluation_reducer(value), complete_data$dimension_reducer),
    evaluations
  )
  components <- intersect(slider_components(evaluations), as.integer(names(complete_data$maps)))
  if (length(components) == 0L) return(list(comparisons = data.frame(), summary = data.frame()))
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  comparisons <- do.call(rbind, lapply(evaluations, function(evaluation) {
    do.call(rbind, lapply(components, function(h) {
      comparison <- mass_stability(
        complete_data$maps[[as.character(h)]], slider_map(evaluation, h), elements, volumes,
        sign_align = FALSE
      )
      comparison$unit_mass_distance <- sqrt(pmax(0, 2 - 2 * comparison$mass_correlation))
      cbind(
        dimension_reducer = evaluation_reducer(evaluation),
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
  elements <- matrix(as.integer(elements), ncol = 4L)
  volumes <- tetrahedral_volumes(points, elements)
  groups <- split(evaluations, vapply(evaluations, evaluation_reducer, character(1)))
  by_reducer <- lapply(groups, function(values) {
    components <- slider_components(values)
    maps <- setNames(lapply(components, function(h) {
      unit_maps <- lapply(values, function(evaluation) {
        value <- slider_map(evaluation, h)
        norm <- sqrt(drop(mass_crossprod(value, value, elements, volumes)))
        if (!is.finite(norm) || norm <= 0) stop("cannot normalize a zero slider map")
        value / norm
      })
      consensus <- Reduce(`+`, unit_maps) / length(unit_maps)
      consensus_norm <- sqrt(drop(mass_crossprod(consensus, consensus, elements, volumes)))
      if (!is.finite(consensus_norm) || consensus_norm <= 0) stop("slider consensus is zero")
      consensus / consensus_norm
    }), as.character(components))
    list(maps = maps, fits = length(values))
  })
  list(by_reducer = by_reducer)
}

plot_slider_correlation <- function(summary, filename, x_label, y_label) {
  if (nrow(summary) == 0L) return(invisible(NULL))
  plot <- ggplot(
    summary,
    aes(retained_components, mean_mass_correlation, colour = dimension_reducer, group = dimension_reducer)
  ) +
    geom_errorbar(
      aes(ymin = mean_mass_correlation - sd_mass_correlation, ymax = mean_mass_correlation + sd_mass_correlation),
      width = 0.12,
      na.rm = TRUE
    ) +
    geom_point(size = 2) +
    scale_x_continuous(breaks = sort(unique(summary$retained_components))) +
    coord_cartesian(ylim = c(-1, 1)) +
    labs(x = x_label, y = y_label, colour = "Dimension reducer") +
    theme_bw() +
    theme(legend.position = "top")
  if (length(unique(summary$retained_components)) > 1L) plot <- plot + geom_line(linewidth = 0.7)
  ggsave(filename, plot, width = 7, height = 4.5, dpi = 180)
}

write_consensus_maps <- function(consensus, aggregate_dir, mesh) {
  root <- file.path(aggregate_dir, "cv_slider_consensus_maps")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  for (reducer in names(consensus$by_reducer)) {
    reducer_result <- consensus$by_reducer[[reducer]]
    reducer_dir <- file.path(root, reducer_slug(reducer))
    dir.create(reducer_dir, recursive = TRUE, showWarnings = FALSE)
    for (h in names(reducer_result$maps)) {
      write.csv(
        data.frame(coefficient = drop(reducer_result$maps[[h]])),
        file.path(reducer_dir, paste0("slider_consensus_h", h, ".csv")),
        row.names = FALSE
      )
    }
    if (!all(3:6 %in% as.integer(names(reducer_result$maps)))) next
    paraview_dir <- file.path(reducer_dir, "paraview")
    dir.create(paraview_dir, recursive = TRUE, showWarnings = FALSE)
    fields <- setNames(
      lapply(3:6, function(h) drop(reducer_result$maps[[as.character(h)]])),
      paste0("slider_consensus_CTRL_unit_H", 3:6)
    )
    write_tetrahedral_vtu(
      file.path(paraview_dir, "cv_slider_consensus.vtu"), mesh$nodes, mesh$elements, fields
    )
    file.copy(
      "tests/brain/paraview/cv_slider_consensus.py",
      file.path(paraview_dir, "cv_slider_consensus.py"),
      overwrite = TRUE
    )
    writeLines(c(
      paste(reducer, "repeated-CV SVM slider consensus maps"),
      "",
      "Run cv_slider_consensus.py from ParaView's Python Shell, or launch:",
      paste0("paraview --script=", file.path(paraview_dir, "cv_slider_consensus.py")),
      "",
      "The scene compares H = 3, 4, 5, 6 with a shared symmetric scale.",
      "Each field is a CTRL-positive, unit-FEM-mass-norm mean across outer fits",
      "for this dimension reducer only. It is not a single fitted-model loading."
    ), file.path(paraview_dir, "README.txt"))
  }
}

aggregate_cv_results <- function(evaluations, aggregate_dir, image_dir, cfg) {
  unlink(list.files(aggregate_dir, pattern = "^cv_.*[.]csv$", full.names = TRUE))
  unlink(file.path(aggregate_dir, "cv_slider_consensus_maps"), recursive = TRUE)
  if (dir.exists(image_dir)) {
    unlink(list.files(image_dir, pattern = "^cv_.*[.](png|pdf)$", full.names = TRUE))
  }
  fold_metrics <- bind_cv_field(evaluations, "fold_metrics")
  predictions <- bind_cv_field(evaluations, "predictions")
  tuning <- bind_cv_field(evaluations, "svm_tuning")
  regularization <- do.call(rbind, lapply(evaluations, function(value) {
    data.frame(
      dimension_reducer = evaluation_reducer(value),
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      component = seq_len(as.integer(value$n_comp)),
      direction_lambda = value$direction_lambda,
      loading_lambda = value$loading_lambda,
      fpca_lambda = value$fpca_lambda
    )
  }))
  resources <- do.call(rbind, lapply(evaluations, function(value) {
    diagnostics <- value$component_diagnostics
    data.frame(
      dimension_reducer = evaluation_reducer(value),
      repeat_index = value$cross_validation$repeat_index,
      fold_index = value$cross_validation$fold_index,
      wall_seconds = as.numeric(value$execution_time),
      peak_ram_mib = value$peak_ram_mib,
      peak_ram_status = if (is.finite(value$peak_ram_mib)) "measured" else "unavailable_in_runtime",
      max_component_iterations = max(diagnostics$iterations),
      any_component_hit_max_iter = any(diagnostics$hit_max_iter),
      all_components_monotone = all(diagnostics$monotone),
      all_components_finite = all(diagnostics$finite_solution),
      projection_max_abs_error = value$projection_max_abs_error
    )
  }))
  oof_metrics <- oof_metrics_by_repeat(predictions)
  performance <- summarize_repeated_metrics(oof_metrics)
  mesh <- load_brain_mesh(cfg$PATH_APPLICATION_DATA)
  stability <- cv_loading_stability(evaluations, mesh$nodes, mesh$elements)
  cross_h <- cv_slider_cross_h_stability(evaluations, mesh$nodes, mesh$elements)
  fpls_evaluations <- Filter(function(value) evaluation_reducer(value) == "R1-fPLS", evaluations)
  complete_data <- load_complete_data_slider_maps(cfg, slider_components(fpls_evaluations))
  against_complete <- cv_slider_vs_complete_data(evaluations, mesh$nodes, mesh$elements, complete_data)
  consensus <- cv_slider_consensus_maps(evaluations, mesh$nodes, mesh$elements)

  write.csv(fold_metrics, file.path(aggregate_dir, "cv_fold_metrics.csv"), row.names = FALSE)
  write.csv(predictions, file.path(aggregate_dir, "cv_predictions.csv"), row.names = FALSE)
  write.csv(tuning, file.path(aggregate_dir, "cv_svm_tuning.csv"), row.names = FALSE)
  write.csv(
    regularization[regularization$dimension_reducer == "R1-fPLS", c(
      "dimension_reducer", "repeat_index", "fold_index", "component",
      "direction_lambda", "loading_lambda"
    )],
    file.path(aggregate_dir, "cv_selected_fpls_lambdas.csv"),
    row.names = FALSE
  )
  write.csv(
    regularization[regularization$dimension_reducer == "fPCR", c(
      "dimension_reducer", "repeat_index", "fold_index", "component", "fpca_lambda"
    )],
    file.path(aggregate_dir, "cv_selected_fpca_lambdas.csv"),
    row.names = FALSE
  )
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
  write_consensus_maps(consensus, aggregate_dir, mesh)

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  plotted_metrics <- c("balanced_accuracy", "roc_auc_schz", "average_precision_schz", "mcc")
  plot_data <- performance$summary[performance$summary$metric %in% plotted_metrics, , drop = FALSE]
  plot_data$metric <- factor(
    plot_data$metric,
    levels = plotted_metrics,
    labels = c("Balanced accuracy", "SCHZ ROC AUC", "SCHZ average precision", "MCC")
  )
  validation_status <- unique(vapply(evaluations, function(value) {
    as.character(value$validation_status)
  }, character(1)))
  run_caption <- if (identical(validation_status, "cross_validation_smoke")) {
    "SMOKE TEST — 1 repeat, 2 folds, H = 1; validates plumbing only, not scientific performance."
  } else {
    "Production repeated cross-validation. Error bars show SD across repeats."
  }
  performance_plot <- ggplot(
    plot_data,
    aes(
      retained_components, mean,
      colour = dimension_reducer, shape = dimension_reducer,
      linetype = dimension_reducer, group = dimension_reducer
    )
  ) +
    geom_errorbar(aes(ymin = mean - sd, ymax = mean + sd), width = 0.12, na.rm = TRUE) +
    geom_point(size = 2) +
    facet_grid(classifier ~ metric) +
    scale_y_continuous(breaks = seq(-1, 1, 0.5)) +
    coord_cartesian(ylim = c(-1, 1)) +
    scale_x_continuous(breaks = sort(unique(plot_data$retained_components))) +
    labs(
      x = "Retained components H",
      y = "Repeated-CV mean +/- SD",
      colour = "Dimension reducer",
      shape = "Dimension reducer",
      linetype = "Dimension reducer",
      caption = run_caption
    ) +
    theme_bw() +
    theme(legend.position = "top")
  if (length(unique(plot_data$retained_components)) > 1L) {
    performance_plot <- performance_plot + geom_line(linewidth = 0.7)
  }
  ggsave(plot_file(image_dir, "cv_out_of_sample_performance"), performance_plot, width = 12, height = 7, dpi = 180)

  if (nrow(stability$summary) > 0L) {
    stability_plot <- ggplot(
      stability$summary,
      aes(
        retained_components, mean_mass_correlation,
        colour = dimension_reducer, shape = dimension_reducer,
        linetype = dimension_reducer, group = dimension_reducer
      )
    ) +
      geom_errorbar(
        aes(ymin = mean_mass_correlation - sd_mass_correlation, ymax = mean_mass_correlation + sd_mass_correlation),
        width = 0.12,
        na.rm = TRUE
      ) +
      geom_point(size = 2) +
      facet_wrap(~ quantity) +
      scale_x_continuous(breaks = sort(unique(stability$summary$retained_components))) +
      coord_cartesian(ylim = c(-1, 1)) +
      labs(
        x = "Retained components H",
        y = "Between-training-fit FEM mass correlation",
        colour = "Dimension reducer",
        shape = "Dimension reducer",
        linetype = "Dimension reducer",
        caption = run_caption
      ) +
      theme_bw() +
      theme(legend.position = "top")
    if (length(unique(stability$summary$retained_components)) > 1L) {
      stability_plot <- stability_plot + geom_line(linewidth = 0.7)
    }
    ggsave(plot_file(image_dir, "cv_loading_reproducibility"), stability_plot, width = 9, height = 5, dpi = 180)
  }
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

  reducers <- sort(unique(predictions$dimension_reducer))
  list(
    repeats = length(unique(predictions$repeat_index)),
    folds = length(unique(predictions$fold_index)),
    fits = length(evaluations),
    fits_by_reducer = as.list(table(vapply(evaluations, evaluation_reducer, character(1)))),
    dimension_reducers = reducers,
    native_components = max(vapply(evaluations, function(value) as.integer(value$n_comp), integer(1))),
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
