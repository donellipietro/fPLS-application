# = ========================================================================== =
# - Test: fPLS brain application - aggregate results
# - Desc: Writes the reported complete-data, resampling, and fPCR summaries.
# - Args: [1] name_main_test
# = ========================================================================== =

rm(list = ls())
graphics.off()

suppressMessages(library(jsonlite))
suppressMessages(library(glue))
suppressMessages(library(ggplot2))
if (capabilities("cairo")) options(bitmapType = "cairo")
plot_file <- function(directory, stem) {
  file.path(directory, paste0(stem, if (capabilities("cairo")) ".png" else ".pdf"))
}
read_matrix <- function(path) as.matrix(suppressWarnings(read.csv(path, check.names = FALSE)))

source("src/utils/directories.R")
source("src/utils/options.R")
source("tests/brain/config.R")
source("tests/brain/utils/generate_options.R")
source("tests/brain/utils/models_evaluation.R")
source("tests/brain/utils/loading_stability.R")
source("tests/brain/utils/intrinsic_slider.R")
source("tests/brain/utils/slider_resampling.R")

args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
if (!requested %in% test_groups$all) stop("unsupported application target: ", requested)
cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)

path_list <- create_paths(test_suite)
queue_dir <- file.path(path_list$queue, requested)
generate_options(test_suite, requested, queue_dir)
option_files <- sort(list.files(queue_dir, pattern = "[.]json$", full.names = TRUE))
expected_evaluations <- character()
evaluations <- list()
for (option_file in option_files) {
  options <- fromJSON(option_file, simplifyVector = TRUE)
  model_names <- as.character(options$model_names)
  expected_evaluations <- c(expected_evaluations, paste(options$name_test, model_names, sep = "::"))
  result_file <- file.path(
    path_list$results, requested, options$name_test, "batch_1",
    "batch_1_results_evaluation.RData"
  )
  if (!file.exists(result_file)) next
  load(result_file)
  for (model_name in intersect(model_names, names(results_evaluation))) {
    value <- results_evaluation[[model_name]]
    value$scenario <- options$name_test
    if (is.null(value$dimension_reducer)) {
      value$dimension_reducer <- if (model_name == "R1_fPLS") "R1-fPLS" else "fPCR"
    }
    evaluations[[paste(options$name_test, model_name, sep = "::")]] <- value
  }
}

status_file <- file.path(aggregate_dir, "application_run_status.json")
if (!length(evaluations)) {
  write_json(list(
    schema_version = 2L, requested = requested, run_complete = FALSE,
    status = "no_results_to_aggregate"
  ), status_file, auto_unbox = TRUE, pretty = TRUE)
  cat("No results available to aggregate.\n")
  quit(save = "no", status = 0)
}
failed <- names(evaluations)[vapply(evaluations, function(value) isTRUE(value$failed), logical(1))]
if (length(failed)) {
  write_json(list(
    schema_version = 2L, requested = requested, run_complete = FALSE,
    status = "native_fit_failed", failed_evaluations = failed
  ), status_file, auto_unbox = TRUE, pretty = TRUE)
  stop("native application fit failed")
}

if (identical(requested, "smoke_overall_mean")) {
  write_json(list(
    schema_version = 2L, requested = requested, run_complete = TRUE,
    status = "smoke_data_preparation_complete",
    validation_status = "smoke_data_preparation_only"
  ), status_file, auto_unbox = TRUE, pretty = TRUE)
  cat("Application smoke aggregation completed.\n")
  quit(save = "no", status = 0)
}

regularization_boundaries <- do.call(rbind, lapply(evaluations, function(value) {
  if (is.null(value$regularization_boundaries)) return(NULL)
  cbind(
    scenario = value$scenario,
    dimension_reducer = value$dimension_reducer,
    value$regularization_boundaries
  )
}))
all_gcv_interior <- is.null(regularization_boundaries) || !any(
  regularization_boundaries$selected_at_lower_boundary |
    regularization_boundaries$selected_at_upper_boundary
)

if (identical(requested, "slider_resampling")) {
  missing <- setdiff(expected_evaluations, names(evaluations))
  if (length(missing)) {
    write_json(list(
      schema_version = 2L, requested = requested, run_complete = FALSE,
      status = "missing_slider_resampling_fits",
      completed_fits = length(evaluations), expected_fits = length(expected_evaluations),
      missing_evaluations = missing
    ), status_file, auto_unbox = TRUE, pretty = TRUE)
    stop("slider-resampling aggregation requires every configured fit")
  }
  validation_status <- unique(vapply(evaluations, function(value) {
    as.character(value$provenance$validation_status)
  }, character(1)))
  if (length(validation_status) != 1L || !validation_status %in% c(
    "slider_resampling_smoke", "slider_resampling_production", "slider_resampling_noncanonical"
  )) stop("slider-resampling evaluations have mixed validation provenance")
  resampling <- aggregate_slider_resampling(evaluations, aggregate_dir, image_dir, cfg)
  write_json(list(
    schema_version = 2L,
    requested = requested,
    run_complete = TRUE,
    status = if (resampling$all_GCV_selections_interior) "complete" else
      "complete_with_GCV_boundary_selection",
    validation_status = validation_status,
    design = list(
      method = "repeated_stratified_delete_one_fold_training_sample_stability",
      repeats = resampling$repeats,
      folds = resampling$folds,
      native_fits = resampling$fits,
      omitted_subjects_usage = "excluded_from_functional_mean_response_GCV_fit_and_slider",
      test_predictions_or_metrics = "not_computed",
      complete_data_reference = "accepted_H3_intrinsic_slider_from_h_stability",
      complete_data_reference_status = resampling$complete_data_reference_status,
      complete_data_reference_map_md5 = resampling$complete_data_reference_map_md5,
      overlap_caveat = "descriptive_stability_not_independent_validation"
    ),
    slider = list(
      definition = "R_H_times_D_H_times_unit_D_H_nu_H",
      retained_components = 3L,
      class_orientation = "positive_is_CTRL",
      posthoc_sign_alignment = FALSE,
      comparable_training_fits = resampling$comparable_H3_fits,
      metrics = c("tetrahedral_P1_FEM_mass_correlation_rho_H3", "relative_FEM_mass_error_e_H3"),
      summary = "intrinsic_fpls_slider_resampling_summary.csv"
    ),
    training_prefix_separation = list(prefixes = 1:6, output = "slider_resampling_Hmin_distribution.csv"),
    all_omitted_data_unused = resampling$all_test_data_unused,
    all_production_GCV_selections_interior = resampling$all_GCV_selections_interior,
    uncertainty = "descriptive_overlapping_training_sets_not_independent_replicates"
  ), status_file, auto_unbox = TRUE, pretty = TRUE)
  cat("Slider-resampling aggregation completed.\n")
  quit(save = "no", status = 0)
}

validation_status <- unique(vapply(evaluations, function(value) {
  as.character(value$provenance$validation_status)
}, character(1)))
expected_validation <- if (requested == "fpcr_h20_separation") {
  "complete_data_exploratory_diagnostic"
} else "complete_data_production"
if (!identical(validation_status, expected_validation)) {
  stop("complete-data aggregation has unexpected validation provenance")
}

resources <- do.call(rbind, lapply(evaluations, function(value) data.frame(
  scenario = value$scenario,
  dimension_reducer = value$dimension_reducer,
  wall_seconds = as.numeric(value$execution_time),
  peak_ram_mib = as.numeric(value$peak_ram_mib),
  max_component_iterations = max(as.integer(value$iteration_count)),
  any_component_hit_max_iter = any(as.logical(value$hit_max_iter)),
  all_components_monotone = all(as.logical(value$monotone)),
  all_components_finite = all(as.logical(value$finite_solution))
)))
write.csv(resources, file.path(aggregate_dir, "complete_data_resources.csv"), row.names = FALSE)
if (!is.null(regularization_boundaries)) write.csv(
  regularization_boundaries,
  file.path(aggregate_dir, "regularization_boundary_diagnostics.csv"),
  row.names = FALSE
)

fpls_loading_gcv <- do.call(rbind, lapply(evaluations, function(value) {
  if (is.null(value$fpls_loading_gcv)) return(NULL)
  cbind(scenario = value$scenario, value$fpls_loading_gcv)
}))
if (!is.null(fpls_loading_gcv)) write.csv(
  fpls_loading_gcv, file.path(aggregate_dir, "fpls_loading_gcv.csv"), row.names = FALSE
)
fpca_gcv <- do.call(rbind, lapply(evaluations, function(value) {
  if (is.null(value$fpca_gcv)) return(NULL)
  cbind(scenario = value$scenario, value$fpca_gcv)
}))
if (!is.null(fpca_gcv)) {
  write.csv(fpca_gcv, file.path(aggregate_dir, "fpca_gcv.csv"), row.names = FALSE)
  fpca_gcv$relative_gcv <- ave(fpca_gcv$gcv, fpca_gcv$component, FUN = function(value) {
    (value - min(value)) / max(abs(min(value)), .Machine$double.eps)
  })
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  curve_plot <- ggplot(fpca_gcv, aes(lambda, relative_gcv)) +
    geom_line(linewidth = 0.5, colour = "#007C91") +
    geom_point(size = 1, colour = "#007C91") +
    geom_point(
      data = fpca_gcv[fpca_gcv$selected_by_fit == 1, , drop = FALSE],
      colour = "#D55E00", size = 2
    ) +
    scale_x_log10() +
    facet_wrap(~ component, scales = "free_y", ncol = 4) +
    labs(x = expression(lambda), y = "Relative GCV above component minimum") +
    theme_bw()
  ggsave(plot_file(image_dir, "fpca_gcv_curves"), curve_plot, width = 10, height = 12, dpi = 180)
}

separation <- do.call(rbind, lapply(evaluations, function(value) {
  if (is.null(value$separation)) return(NULL)
  cbind(
    scenario = value$scenario,
    dimension_reducer = value$dimension_reducer,
    requested_components = value$n_comp,
    value$separation
  )
}))
write.csv(separation, file.path(aggregate_dir, "separation_by_H.csv"), row.names = FALSE)
dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
separation_long <- rbind(
  data.frame(prefix_components = separation$prefix_components, metric = "AUC", value = separation$auc),
  data.frame(prefix_components = separation$prefix_components, metric = "Sensitivity", value = separation$sensitivity),
  data.frame(prefix_components = separation$prefix_components, metric = "Specificity", value = separation$specificity)
)
separation_plot <- ggplot(separation_long, aes(prefix_components, value, colour = metric)) +
  geom_line(linewidth = 0.7) + geom_point(size = 2) +
  scale_x_continuous(breaks = sort(unique(separation$prefix_components))) +
  scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  labs(x = "Component prefix H", y = "In-sample separation", colour = NULL) +
  theme_bw() + theme(legend.position = "top")
ggsave(plot_file(image_dir, "separation_by_H"), separation_plot, width = 7, height = 4.5, dpi = 180)

first_perfect <- if (any(separation$perfect_separation)) {
  as.character(min(separation$prefix_components[separation$perfect_separation]))
} else paste0("none_up_to_H", max(separation$prefix_components))

if (identical(requested, "h_stability")) {
  scenario <- "h_stability_H6"
  raw_dir <- file.path(path_list$results, requested, scenario, "batch_1", "raw", "R1_fPLS")
  batch_dir <- dirname(dirname(raw_dir))
  points <- read_matrix(file.path(raw_dir, "points.csv"))
  elements <- matrix(as.integer(read_matrix(file.path(raw_dir, "elements.csv"))), ncol = 4L)
  x_loadings <- read_matrix(file.path(raw_dir, "x_loadings_coefficients.csv"))
  y_loadings <- read_matrix(file.path(raw_dir, "y_loadings.csv"))
  scores <- read_matrix(file.path(raw_dir, "x_latent_scores.csv"))
  prepared_data <- readRDS(file.path(batch_dir, "prepared_data.rds"))
  volumes <- tetrahedral_volumes(points, elements)

  sliders <- setNames(lapply(3:6, function(h) {
    standardized_intrinsic_fpls_slider(scores, x_loadings, y_loadings, h)
  }), as.character(3:6))
  reference <- matrix(sliders[["3"]]$loading, ncol = 1L)
  intrinsic_stability <- do.call(rbind, lapply(4:6, function(h) cbind(
    reference_components = 3L,
    retained_components = h,
    mass_stability(reference, matrix(sliders[[as.character(h)]]$loading, ncol = 1L), elements, volumes)
  )))
  intrinsic_stability$rho_H <- intrinsic_stability$mass_correlation
  intrinsic_stability$e_H <- intrinsic_stability$relative_mass_error
  write.csv(intrinsic_stability[c(
    "reference_components", "retained_components", "rho_H", "e_H",
    "reference_mass_norm", "candidate_mass_norm", "sign_alignment"
  )], file.path(aggregate_dir, "intrinsic_fpls_slider_stability_by_H.csv"), row.names = FALSE)

  pad <- function(values) c(values, rep(NA_real_, 6L - length(values)))
  coordinates <- do.call(rbind, lapply(3:6, function(h) {
    slider <- sliders[[as.character(h)]]
    as.data.frame(as.list(c(
      retained_components = h,
      response_norm = slider$response_norm,
      setNames(pad(slider$unit_standardized_normal), paste0("q_t", 1:6)),
      setNames(pad(slider$score_center), paste0("score_center_t", 1:6)),
      setNames(pad(slider$score_scale), paste0("score_scale_t", 1:6))
    )), check.names = FALSE)
  }))
  write.csv(coordinates, file.path(aggregate_dir, "intrinsic_fpls_slider_coordinates_by_H.csv"), row.names = FALSE)
  map_dir <- file.path(aggregate_dir, "intrinsic_fpls_slider_maps")
  dir.create(map_dir, recursive = TRUE, showWarnings = FALSE)
  for (h in 3:6) write.csv(
    data.frame(coefficient = sliders[[as.character(h)]]$loading),
    file.path(map_dir, glue::glue("reconstruction_loading_h{h}.csv")),
    row.names = FALSE
  )

  h3 <- sliders[["3"]]
  h3_threshold <- separation$threshold[separation$prefix_components == 3L]
  h3_threshold_standardized <- (
    h3_threshold - sum(y_loadings[1, 1:3] * h3$score_center)
  ) / h3$response_norm
  standardized_h3 <- sweep(
    sweep(scores[, 1:3, drop = FALSE], 2L, h3$score_center, "-"),
    2L, h3$score_scale, "/"
  )
  write.csv(data.frame(
    subject = seq_len(nrow(scores)),
    group = prepared_data$labels,
    z1 = standardized_h3[, 1], z2 = standardized_h3[, 2], z3 = standardized_h3[, 3],
    intrinsic_slider_coordinate = h3$coordinate,
    intrinsic_slider_threshold = h3_threshold_standardized
  ), file.path(aggregate_dir, "intrinsic_fpls_scores_H3.csv"), row.names = FALSE)

  beta_coefficients <- setNames(lapply(3:6, function(h) read_matrix(
    file.path(raw_dir, glue::glue("beta_coefficients_h{h}.csv"))
  )), as.character(3:6))
  beta_summary <- beta_stability(beta_coefficients, points, elements)$summary
  write.csv(
    subset(beta_summary, retained_components %in% 4:6),
    file.path(aggregate_dir, "beta_stability_by_H.csv"), row.names = FALSE
  )

  plot_values <- rbind(
    data.frame(retained_components = intrinsic_stability$retained_components, metric = "rho_H", value = intrinsic_stability$rho_H),
    data.frame(retained_components = intrinsic_stability$retained_components, metric = "e_H", value = intrinsic_stability$e_H)
  )
  stability_plot <- ggplot(plot_values, aes(retained_components, value, colour = metric)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2) +
    facet_wrap(~ metric, scales = "free_y") + scale_x_continuous(breaks = 4:6) +
    labs(x = "Retained components H", y = "Comparison with H=3 intrinsic slider") +
    theme_bw() + theme(legend.position = "none")
  ggsave(
    plot_file(image_dir, "intrinsic_fpls_slider_stability_by_H"),
    stability_plot, width = 7, height = 4.5, dpi = 180
  )

  boundary_status <- list(
    reference = "H3_standardized_intrinsic_fPLS_slider_loading",
    comparisons = "H4_to_H6_standardized_intrinsic_fPLS_slider_loadings",
    definition = "R_H_times_D_H_times_unit_D_H_nu_H",
    metrics = c("tetrahedral_P1_FEM_mass_correlation_rho_H", "relative_FEM_mass_error_e_H"),
    aggregate = "intrinsic_fpls_slider_stability_by_H.csv"
  )
  beta_status <- list(
    reference = "native_Beta_H3", comparisons = "native_Beta_H4_to_H6",
    metric = "tetrahedral_P1_FEM_mass_relative_norm_without_sign_flip"
  )
} else {
  boundary_status <- "not_requested_for_fpcr_H20_separation_diagnostic"
  beta_status <- "not_requested_for_fpcr"
}

write_json(list(
  schema_version = 2L,
  requested = requested,
  dimension_reducer = if (requested == "h_stability") "R1-fPLS" else "fPCR",
  run_complete = TRUE,
  status = if (all_gcv_interior) "complete" else "complete_with_GCV_boundary_selection",
  validation_status = validation_status,
  all_production_GCV_selections_interior = all_gcv_interior,
  first_H_with_perfect_in_sample_separation = first_perfect,
  prefix_diagnostics = paste0("computed_from_single_H", max(separation$requested_components), "_fit"),
  separation_orientation = list(
    score_positive_class = "CTRL", auc_positive_class = "CTRL",
    sensitivity_class = "SCHZ", specificity_class = "CTRL"
  ),
  decision_boundary_loading_stability = boundary_status,
  beta_stability = beta_status,
  complete_data_resources = "complete_data_resources.csv"
), status_file, auto_unbox = TRUE, pretty = TRUE)
cat("Application aggregation completed.\n")
