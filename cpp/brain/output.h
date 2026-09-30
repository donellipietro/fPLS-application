#ifndef FPLS_BRAIN_OUTPUT_H
#define FPLS_BRAIN_OUTPUT_H

#include "support.h"

/** @brief export the training mean in coefficient and nodal form together with its GCV curve */
inline void write_functional_mean_output(
  const std::filesystem::path& output_dir, const functional_mean_fit& mean_fit,
  const std::vector<double>& mean_lambda_grid) {
    std::filesystem::create_directories(output_dir);
    write_csv(output_file(output_dir, "functional_mean_coefficients.csv"), mean_fit.coefficients);
    write_csv(output_file(output_dir, "functional_mean_locations.csv"), mean_fit.locations);
    // preserve the candidate grid order so lambda, EDF and GCV remain directly comparable
    matrix_t mean_gcv_diagnostics(mean_lambda_grid.size(), 3);
    for (std::size_t index = 0; index < mean_lambda_grid.size(); ++index) {
        mean_gcv_diagnostics(index, 0) = mean_lambda_grid[index];
        mean_gcv_diagnostics(index, 1) = mean_fit.effective_degrees_of_freedom[index];
        mean_gcv_diagnostics(index, 2) = mean_fit.gcv_scores[index];
    }
    write_csv(
      output_file(output_dir, "functional_mean_gcv.csv"), mean_gcv_diagnostics,
      std::vector<std::string> {"lambda", "edf", "gcv"});
}

/** @brief export fPLS latent quantities, component-prefix fits and calibration/convergence metadata */
template <typename Space, typename Model>
int write_fpls_output(
  const simulation_parameters& params, const Space& space, const Model& model, const matrix_t& X, const matrix_t& Y,
  const functional_mean_fit& mean_fit, time_point_t wall_start, time_point_t setup_end, time_point_t fit_end,
  time_point_t centering_start, time_point_t centering_end) {
    const auto& direction_lambdas = model.direction_lambda();
    const auto& loading_lambdas = model.loading_lambda();
    // store functional directions/loadings as basis coefficients and scores as subject-by-component matrices
    write_csv(output_file(params.output_dir, "x_space_directions_coefficients.csv"), model.X_space_directions());
    write_csv(output_file(params.output_dir, "y_space_directions.csv"), model.Y_space_directions());
    write_csv(output_file(params.output_dir, "x_latent_scores.csv"), model.X_latent_scores());
    write_csv(output_file(params.output_dir, "y_latent_scores.csv"), model.Y_latent_scores());
    write_csv(output_file(params.output_dir, "x_loadings_coefficients.csv"), model.X_loadings());
    write_csv(output_file(params.output_dir, "y_loadings.csv"), model.Y_loadings());
    write_csv(output_file(params.output_dir, "direction_lambdas.csv"), direction_lambdas);
    write_csv(output_file(params.output_dir, "loading_lambdas.csv"), loading_lambdas);
    // export only the saved candidate curves whose fitted selection is at a grid endpoint
    const matrix_t loading_gcv_diagnostics = fpls_loading_gcv_diagnostics(model);
    const bool has_loading_gcv_diagnostics = params.calibration == "gcv" && loading_gcv_diagnostics.rows() > 0;
    const bool loading_gcv_minimum_matches_fit =
      !has_loading_gcv_diagnostics ||
      (loading_gcv_diagnostics.col(4) - loading_gcv_diagnostics.col(5)).squaredNorm() == 0;
    if (has_loading_gcv_diagnostics) {
        write_csv(
          output_file(params.output_dir, "fpls_loading_gcv.csv"), loading_gcv_diagnostics,
          std::vector<std::string> {"component", "lambda", "edf", "gcv", "selected_by_fit", "grid_minimum"});
    }
    // pair each direction's objective history with its iteration count and stopping diagnostics
    matrix_t component_diagnostics(params.n_comp, 6);
    for (int h = 0; h < params.n_comp; ++h) {
        const auto& history = model.direction_objective_history()[h];
        Eigen::Map<const matrix_t> history_matrix(history.data(), history.size(), 1);
        write_csv(
          output_file(params.output_dir, "objective_history_h" + std::to_string(h + 1) + ".csv"), history_matrix);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.direction_iterations()[h];
        component_diagnostics(h, 2) = model.direction_monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ? std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.direction_iterations()[h] >= params.max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) = !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;
        std::cout << "- Component " << h + 1 << '/' << params.n_comp
                  << " completed: direction lambda=" << direction_lambdas(h, 0)
                  << ", iterations=" << model.direction_iterations()[h] << std::endl;
    }
    write_csv(
      output_file(params.output_dir, "component_diagnostics.csv"), component_diagnostics,
      std::vector<std::string> {"component", "iterations", "monotone", "objective", "hit_max_iter", "finite_solution"});

    // each suffix h identifies a model using the first h components, including optional reconstructions and beta
    json component_files = json::array();
    for (int h = 1; h <= params.n_comp; ++h) {
        const std::string suffix = "_h" + std::to_string(h) + ".csv";
        write_csv(output_file(params.output_dir, "y_hat" + suffix), model.fitted(h));
        json files {
          {"component", h               },
          {"y_hat",     "y_hat" + suffix}
        };
        if (params.write_reconstructions) {
            write_csv(output_file(params.output_dir, "x_hat_locations" + suffix), model.reconstructed(h));
            files["x_hat_locations"] = "x_hat_locations" + suffix;
        }
        if (params.write_beta) {
            write_csv(output_file(params.output_dir, "beta_coefficients" + suffix), model.Beta(h));
            files["beta_coefficients"] = "beta_coefficients" + suffix;
        }
        component_files.push_back(std::move(files));
    }
    const auto output_end = std::chrono::steady_clock::now();

    // report setup (including functional-mean estimation), model fitting and CSV output separately
    const double setup_seconds = std::chrono::duration<double>(setup_end - wall_start).count();
    const double fit_seconds = std::chrono::duration<double>(fit_end - setup_end).count();
    const double output_seconds = std::chrono::duration<double>(output_end - fit_end).count();
    const double wall_seconds = std::chrono::duration<double>(output_end - wall_start).count();
    std::vector<int> monotone;
    monotone.reserve(model.direction_monotone().size());
    for (bool value : model.direction_monotone()) monotone.push_back(value ? 1 : 0);

    // retain centering/calibration settings, input provenance and the component-file manifest for reproducibility
    json telemetry_json;
    telemetry_json["schema_version"] = 4;
    telemetry_json["model"] = "R1_fPLS";
    telemetry_json["mode"] = "native_fdaPDE_cpp";
    telemetry_json["discretization"] = "tetrahedral_fem";
    telemetry_json["center"] = false;
    telemetry_json["centering"] = "training_overall_gcv_smoothed_functional_mean";
    telemetry_json["mean_lambda_grid"] = params.mean_lambda_grid;
    telemetry_json["mean_gcv_probes"] = params.mean_gcv_probes;
    telemetry_json["mean_gcv_seed"] = params.mean_gcv_seed;
    telemetry_json["mean_selected_lambda"] = mean_fit.selected_lambda;
    telemetry_json["mean_effective_degrees_of_freedom"] = mean_fit.effective_degrees_of_freedom;
    telemetry_json["mean_gcv_scores"] = mean_fit.gcv_scores;
    telemetry_json["mean_formula"] = "argmin_lambda m/(m-edf_lambda)^2*||S_lambda*colMeans(X_train)-"
                                     "colMeans(X_train)||_2^2";
    telemetry_json["mean_scope"] = "native_fit_training_rows_only";
    telemetry_json["calibration"] = params.calibration;
    telemetry_json["fit_includes_gcv"] = params.calibration == "gcv";
    telemetry_json["write_reconstructions"] = params.write_reconstructions;
    telemetry_json["write_beta"] = params.write_beta;
    telemetry_json["n_units"] = X.rows();
    telemetry_json["n_locations"] = X.cols();
    telemetry_json["n_responses"] = Y.cols();
    telemetry_json["n_components"] = params.n_comp;
    telemetry_json["n_basis"] = space.n_dofs();
    telemetry_json["max_iter"] = params.max_iter;
    telemetry_json["tolerance"] = params.tolerance;
    telemetry_json["gcv_probes"] = params.gcv_probes;
    telemetry_json["gcv_seed"] = params.gcv_seed;
    telemetry_json["lambda_grid"] = params.lambda_grid;
    telemetry_json["fpls_loading_gcv_file"] =
      has_loading_gcv_diagnostics ?
        "fpls_loading_gcv.csv" :
        (params.calibration == "gcv" ? "not_required_no_loading_boundary" : "not_applicable");
    telemetry_json["fpls_loading_gcv_scope"] = "boundary_selected_loadings_only";
    telemetry_json["fpls_loading_gcv_minimum_matches_fit"] = loading_gcv_minimum_matches_fit;
    telemetry_json["fpls_loading_gcv_source"] = "calibration_evaluations_saved_during_fit";
    telemetry_json["diagnostic_refits"] = 0;
    telemetry_json["fixed_direction_lambda"] = params.fixed_direction_lambda;
    telemetry_json["fixed_loading_lambda"] = params.fixed_loading_lambda;
    telemetry_json["setup_seconds"] = setup_seconds;
    telemetry_json["centering_seconds"] = std::chrono::duration<double>(centering_end - centering_start).count();
    telemetry_json["fit_seconds"] = fit_seconds;
    telemetry_json["output_seconds"] = output_seconds;
    telemetry_json["wall_seconds"] = wall_seconds;
    telemetry_json["iteration_counts_available"] = true;
    telemetry_json["iteration_counts"] = model.direction_iterations();
    telemetry_json["monotone"] = monotone;
    telemetry_json["component_files"] = component_files;
    telemetry_json["provenance"] = params.provenance;
    std::ofstream telemetry(output_file(params.output_dir, "telemetry.json"));
    telemetry << telemetry_json.dump(2) << '\n';

    std::cout << "fPLS fit completed." << std::endl;

    return 0;
}

/** @brief export fPCR score projections, component-prefix fits and explicit-EDF calibration metadata */
template <typename Space, typename Model>
int write_fpcr_output(
  const simulation_parameters& params, const Space& space, const Model& model, const matrix_t& X, const matrix_t& Y,
  const functional_mean_fit& mean_fit, time_point_t wall_start, time_point_t setup_end, time_point_t fit_end,
  time_point_t centering_start, time_point_t centering_end) {
    const auto& scores = model.X_latent_scores();
    const auto& projection_scales = model.projection_scales();
    const auto& projection_errors = model.projection_errors();
    const auto& full_coefficients = model.score_coefficients();
    // retain the sequential score scale together with normalized functional loading coefficients
    write_csv(output_file(params.output_dir, "x_space_directions_coefficients.csv"), model.loading_directions());
    write_csv(output_file(params.output_dir, "x_latent_scores.csv"), scores);
    write_csv(output_file(params.output_dir, "x_loadings_coefficients.csv"), model.F());
    write_csv(output_file(params.output_dir, "score_projection_scales.csv"), projection_scales);

    // export the selected fPCA lambda and the candidate EDF/GCV values for each component
    const matrix_t fpca_lambdas = model.lambda();
    write_csv(output_file(params.output_dir, "fpca_lambdas.csv"), fpca_lambdas);
    if (params.calibration == "gcv") {
        const auto& grid = model.lambda_grid();
        matrix_t fpca_gcv(params.n_comp * grid.rows(), 5);
        Eigen::Index row = 0;
        for (int h = 0; h < params.n_comp; ++h) {
            for (Eigen::Index index = 0; index < grid.rows(); ++index) {
                fpca_gcv.row(row++) << h + 1, grid(index, 0), model.gcv_edf()[h][index], model.gcv_values()[h][index],
                  index == model.selected_indices()[h] ? 1.0 : 0.0;
            }
        }
        write_csv(
          output_file(params.output_dir, "fpca_gcv.csv"), fpca_gcv,
          std::vector<std::string> {"component", "lambda", "edf", "gcv", "selected_by_fit"});
    }
    // fPCR has no separate fPLS direction/loading lambdas; compatibility files mark them as unavailable
    const matrix_t unavailable_lambdas = matrix_t::Constant(params.n_comp, 1, std::numeric_limits<double>::quiet_NaN());
    write_csv(output_file(params.output_dir, "direction_lambdas.csv"), unavailable_lambdas);
    write_csv(output_file(params.output_dir, "loading_lambdas.csv"), unavailable_lambdas);

    // pair each fPCA objective history with its iteration count, stopping status and finite-solution checks
    matrix_t component_diagnostics(params.n_comp, 6);
    const auto& objective_histories = model.objective_history();
    for (int h = 0; h < params.n_comp; ++h) {
        const auto& history = objective_histories[h];
        Eigen::Map<const matrix_t> history_matrix(history.data(), history.size(), 1);
        write_csv(
          output_file(params.output_dir, "objective_history_h" + std::to_string(h + 1) + ".csv"), history_matrix);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.iterations()[h];
        component_diagnostics(h, 2) = model.monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ? std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.iterations()[h] >= params.max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) = model.F().col(h).allFinite() && scores.col(h).allFinite() &&
                                          (history.empty() || std::isfinite(history.back())) ?
                                        1.0 :
                                        0.0;
        std::cout << "- Component " << h + 1 << '/' << params.n_comp << " completed: fPCA lambda=" << fpca_lambdas(h, 0)
                  << ", iterations=" << model.iterations()[h] << std::endl;
    }
    write_csv(
      output_file(params.output_dir, "component_diagnostics.csv"), component_diagnostics,
      std::vector<std::string> {"component", "iterations", "monotone", "objective", "hit_max_iter", "finite_solution"});

    // serialize the predictions and optional functional outputs already computed for every OLS prefix
    matrix_t y_latent_scores(X.rows(), params.n_comp * Y.cols());
    matrix_t response_diagnostics(params.n_comp * Y.cols(), 4);
    json component_files = json::array();
    for (int h = 1; h <= params.n_comp; ++h) {
        const matrix_t y_hat = model.fitted(h);
        const std::string suffix = "_h" + std::to_string(h) + ".csv";
        write_csv(output_file(params.output_dir, "y_hat" + suffix), y_hat);
        json files {
          {"component", h               },
          {"y_hat",     "y_hat" + suffix}
        };

        if (params.write_reconstructions) {
            write_csv(output_file(params.output_dir, "x_hat_locations" + suffix), model.reconstructed(h));
            files["x_hat_locations"] = "x_hat_locations" + suffix;
        }
        if (params.write_beta) {
            write_csv(output_file(params.output_dir, "beta_coefficients" + suffix), model.Beta(h));
            files["beta_coefficients"] = "beta_coefficients" + suffix;
        }
        // retain per-response errors without flattening a multivariate response into one scalar diagnostic
        for (Eigen::Index response = 0; response < Y.cols(); ++response) {
            const double sse = (Y.col(response) - y_hat.col(response)).squaredNorm();
            response_diagnostics.row((h - 1) * Y.cols() + response) << h, response + 1, sse, sse / Y.rows();
        }
        component_files.push_back(std::move(files));
    }
    write_csv(
      output_file(params.output_dir, "response_diagnostics.csv"), response_diagnostics,
      std::vector<std::string> {"component", "response", "sse", "mse"});

    // response-side compatibility files contain each score's contribution to the full regression fit
    for (int h = 0; h < params.n_comp; ++h) {
        y_latent_scores.middleCols(h * Y.cols(), Y.cols()) = scores.col(h) * full_coefficients.row(h);
    }
    write_csv(output_file(params.output_dir, "y_space_directions.csv"), full_coefficients.transpose());
    write_csv(output_file(params.output_dir, "y_loadings.csv"), full_coefficients.transpose());
    write_csv(output_file(params.output_dir, "y_latent_scores.csv"), y_latent_scores);

    const auto output_end = std::chrono::steady_clock::now();
    // report setup (including functional-mean estimation), model fitting and CSV output separately
    const double setup_seconds = std::chrono::duration<double>(setup_end - wall_start).count();
    const double fit_seconds = std::chrono::duration<double>(fit_end - setup_end).count();
    const double output_seconds = std::chrono::duration<double>(output_end - fit_end).count();
    const double wall_seconds = std::chrono::duration<double>(output_end - wall_start).count();
    std::vector<int> monotone;
    monotone.reserve(model.monotone().size());
    for (bool value : model.monotone()) monotone.push_back(value ? 1 : 0);

    // retain explicit EDF control and projection diagnostics alongside centering settings and input provenance
    json telemetry_json;
    telemetry_json["schema_version"] = 4;
    telemetry_json["model"] = "fPCR";
    telemetry_json["mode"] = "native_fdaPDE_cpp";
    telemetry_json["discretization"] = "tetrahedral_fem";
    telemetry_json["fpca_solver"] = "power_iteration";
    telemetry_json["fpca_initialization"] = "exact_svd";
    telemetry_json["fpca_implementation"] = "public_fdaPDE_fPCR_with_explicit_edf_control";
    telemetry_json["fpca_gcv_edf"] = json {
      {"applied",            params.calibration == "gcv"               },
      {"method",             "hutchinson"                              },
      {"probe_count_source", "gcv_probes"                              },
      {"seed_source",        "gcv_seed"                                },
      {"seed_mode",          "explicit_deterministic"                  },
      {"cache",              "per_lambda_shared_across_components"     },
      {"diagnostics_source", "calibration_evaluations_saved_during_fit"}
    };
    telemetry_json["center"] = false;
    telemetry_json["centering"] = "training_overall_gcv_smoothed_functional_mean";
    telemetry_json["mean_lambda_grid"] = params.mean_lambda_grid;
    telemetry_json["mean_gcv_probes"] = params.mean_gcv_probes;
    telemetry_json["mean_gcv_seed"] = params.mean_gcv_seed;
    telemetry_json["mean_selected_lambda"] = mean_fit.selected_lambda;
    telemetry_json["mean_effective_degrees_of_freedom"] = mean_fit.effective_degrees_of_freedom;
    telemetry_json["mean_gcv_scores"] = mean_fit.gcv_scores;
    telemetry_json["mean_formula"] = "argmin_lambda m/(m-edf_lambda)^2*||S_lambda*colMeans(X_train)-"
                                     "colMeans(X_train)||_2^2";
    telemetry_json["mean_scope"] = "native_fit_training_rows_only";
    telemetry_json["calibration"] = params.calibration;
    telemetry_json["fit_includes_gcv"] = params.calibration == "gcv";
    telemetry_json["write_reconstructions"] = params.write_reconstructions;
    telemetry_json["write_beta"] = params.write_beta;
    telemetry_json["n_units"] = X.rows();
    telemetry_json["n_locations"] = X.cols();
    telemetry_json["n_responses"] = Y.cols();
    telemetry_json["n_components"] = params.n_comp;
    telemetry_json["n_basis"] = space.n_dofs();
    telemetry_json["max_iter"] = params.max_iter;
    telemetry_json["tolerance"] = params.tolerance;
    telemetry_json["gcv_probes"] = params.gcv_probes;
    telemetry_json["gcv_seed"] = params.gcv_seed;
    telemetry_json["lambda_grid"] = params.lambda_grid;
    telemetry_json["fixed_fpca_lambda"] = params.fixed_fpca_lambda;
    telemetry_json["fpca_lambdas"] = std::vector<double>(fpca_lambdas.data(), fpca_lambdas.data() + params.n_comp);
    telemetry_json["fpca_gcv_file"] = params.calibration == "gcv" ? "fpca_gcv.csv" : "not_applicable_fixed_lambda";
    telemetry_json["score_projection_scales"] =
      std::vector<double>(projection_scales.data(), projection_scales.data() + params.n_comp);
    telemetry_json["score_projection_reference"] = "model.S()";
    telemetry_json["score_projection_component_max_abs_error"] = projection_errors;
    telemetry_json["score_projection_max_abs_error"] =
      *std::max_element(projection_errors.begin(), projection_errors.end());
    telemetry_json["score_projection_definition"] =
      "sequential_residual_times_alpha_F_with_alpha_loading_norm_over_raw_"
      "score_norm";
    telemetry_json["regression"] = "training_only_OLS_refit_for_each_component_prefix";
    telemetry_json["diagnostic_refits"] = 0;
    telemetry_json["response_diagnostics_file"] = "response_diagnostics.csv";
    telemetry_json["y_latent_scores_definition"] = "full_model_score_contributions_per_response";
    telemetry_json["y_latent_scores_column_order"] = "component_major_response_minor";
    telemetry_json["y_latent_scores_columns"] = json::array();
    for (int h = 1; h <= params.n_comp; ++h) {
        for (Eigen::Index response = 1; response <= Y.cols(); ++response) {
            telemetry_json["y_latent_scores_columns"].push_back(
              json {
                {"component", h       },
                {"response",  response}
            });
        }
    }
    telemetry_json["setup_seconds"] = setup_seconds;
    telemetry_json["centering_seconds"] = std::chrono::duration<double>(centering_end - centering_start).count();
    telemetry_json["fit_seconds"] = fit_seconds;
    telemetry_json["output_seconds"] = output_seconds;
    telemetry_json["wall_seconds"] = wall_seconds;
    telemetry_json["iteration_counts_available"] = true;
    telemetry_json["iteration_counts"] = model.iterations();
    telemetry_json["monotone"] = monotone;
    telemetry_json["component_files"] = component_files;
    telemetry_json["provenance"] = params.provenance;
    std::ofstream telemetry(output_file(params.output_dir, "telemetry.json"));
    telemetry << telemetry_json.dump(2) << '\n';

    std::cout << "fPCR fit completed." << std::endl;
    return 0;
}

#endif
