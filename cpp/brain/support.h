#ifndef FPLS_BRAIN_SUPPORT_H
#define FPLS_BRAIN_SUPPORT_H

#include <fdaPDE/models.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace fdapde;
using nlohmann::json;

using matrix_t = Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic>;
using vector_t = Eigen::Matrix<double, Eigen::Dynamic, 1>;

/** @brief smoothed training mean and its GCV selection diagnostics */
struct functional_mean_fit {
    vector_t coefficients;
    vector_t locations;
    double selected_lambda;
    std::vector<double> effective_degrees_of_freedom;
    std::vector<double> gcv_scores;
};

/** @brief smooth the training empirical mean and select its penalty by GCV over observation nodes */
inline functional_mean_fit fit_functional_mean_gcv(
  const matrix_t& X, fdapde::internals::fe_ls_elliptic& smoother, const std::vector<double>& lambda_grid,
  int gcv_probes, int gcv_seed) {
    if (
      lambda_grid.empty() || gcv_probes < 1 ||
      std::any_of(
        lambda_grid.begin(), lambda_grid.end(), [](double value) { return !std::isfinite(value) || value <= 0; })) {
        throw std::runtime_error("invalid functional-mean GCV configuration");
    }

    // average across training subjects, leaving one empirical mean value per mesh node
    const vector_t empirical_mean = X.colwise().mean().transpose();
    smoother.update_response(empirical_mean);
    functional_mean_fit result;
    result.effective_degrees_of_freedom.reserve(lambda_grid.size());
    result.gcv_scores.reserve(lambda_grid.size());

    // compare candidates using node-wise residuals corrected by the smoother effective degrees of freedom
    std::size_t selected = 0;
    double best_gcv = std::numeric_limits<double>::infinity();
    for (std::size_t index = 0; index < lambda_grid.size(); ++index) {
        const double lambda = lambda_grid[index];
        smoother.fit(lambda);
        const double edf = smoother.edf(lambda, gcv_probes, gcv_seed);
        const double residual_degrees_of_freedom = static_cast<double>(X.cols()) - edf;
        if (!std::isfinite(edf) || residual_degrees_of_freedom <= 0) {
            throw std::runtime_error("functional-mean GCV has invalid residual degrees of freedom");
        }
        const double gcv = (static_cast<double>(X.cols()) / std::pow(residual_degrees_of_freedom, 2)) *
                           (smoother.fn() - empirical_mean).squaredNorm();
        if (!std::isfinite(gcv)) throw std::runtime_error("functional-mean GCV score is non-finite");
        result.effective_degrees_of_freedom.push_back(edf);
        result.gcv_scores.push_back(gcv);
        if (gcv < best_gcv) {
            best_gcv = gcv;
            selected = index;
        }
    }

    // refit the minimizing candidate because the loop leaves the smoother at the last grid value
    result.selected_lambda = lambda_grid[selected];
    smoother.fit(result.selected_lambda);
    result.coefficients = smoother.f();
    result.locations = smoother.fn();
    if (!result.coefficients.allFinite() || !result.locations.allFinite())
        throw std::runtime_error("functional-mean fit is non-finite");
    return result;
}

/** @brief serialize saved loading calibration evaluations for components selected at a grid endpoint */
template <typename Model> matrix_t fpls_loading_gcv_diagnostics(const Model& model) {
    const auto& grid = model.loading_lambda_grid();
    const auto& selected = model.loading_selected_indices();
    const auto& gcv = model.loading_gcv_values();
    const auto& edf = model.loading_gcv_edfs();
    int n_boundary_components = 0;
    for (int index : selected) {
        if (index == 0 || index == grid.rows() - 1) ++n_boundary_components;
    }
    matrix_t diagnostics(n_boundary_components * grid.rows(), 6);
    Eigen::Index row = 0;
    for (std::size_t h = 0; h < selected.size(); ++h) {
        if (selected[h] != 0 && selected[h] != grid.rows() - 1) continue;
        // use candidate positions so repeated lambda values still identify the selected evaluation unambiguously
        const auto minimum = std::min_element(gcv[h].begin(), gcv[h].end());
        const auto minimum_index = std::distance(gcv[h].begin(), minimum);
        for (Eigen::Index index = 0; index < grid.rows(); ++index) {
            diagnostics.row(row++) << h + 1, grid(index, 0), edf[h][index], gcv[h][index],
              index == selected[h] ? 1.0 : 0.0, index == minimum_index ? 1.0 : 0.0;
        }
    }
    return diagnostics;
}

/** @brief read a numeric CSV matrix through the fdaPDE table reader */
inline matrix_t read_matrix(const std::string& file) {
    const std::filesystem::path path(file);
    const std::string readable_path =
      path.is_absolute() ? std::filesystem::relative(path, std::filesystem::current_path()).string() : file;
    return read_csv<double>(readable_path, true, false).as_matrix();
}

/** @brief resolve an output filename within the configured result directory */
inline std::string output_file(const std::filesystem::path& output_dir, const std::string& name) {
    return (output_dir / name).string();
}

using time_point_t = std::chrono::steady_clock::time_point;

/** @brief parse the JSON parameter file or report an unreadable input */
inline json read_parameter_file(const std::string& file) {
    std::ifstream input(file);
    if (!input) throw std::runtime_error("cannot open parameter file");
    return json::parse(input);
}

/** @brief validated mesh inputs, centering and model settings for the brain application */
struct application_parameters {
    std::string model_name;
    int n_comp;
    int max_iter;
    double tolerance;
    int gcv_probes;
    int gcv_seed;
    int mean_gcv_probes;
    int mean_gcv_seed;
    std::string calibration;
    std::vector<double> lambda_grid;
    std::vector<double> mean_lambda_grid;
    double fixed_direction_lambda;
    double fixed_loading_lambda;
    std::filesystem::path output_dir;
    bool write_reconstructions;
    bool write_beta;
    std::string X_file;
    std::string Y_file;
    std::string nodes_file;
    std::string elements_file;
    std::string boundary_file;
    double fixed_fpca_lambda = 0;
    json provenance;
};

/** @brief read application inputs and validate model, centering and solver settings */
inline application_parameters read_parameters(const json& values) {
    application_parameters params;
    params.model_name = values.at("model").get<std::string>();
    params.n_comp = values.at("n_comp").get<int>();
    params.max_iter = values.at("max_iter").get<int>();
    params.tolerance = values.at("tolerance").get<double>();
    params.gcv_probes = values.at("gcv_probes").get<int>();
    params.gcv_seed = values.at("gcv_seed").get<int>();
    params.mean_gcv_probes = values.at("mean_gcv_probes").get<int>();
    params.mean_gcv_seed = values.at("mean_gcv_seed").get<int>();
    params.calibration = values.at("calibration").get<std::string>();
    params.lambda_grid = values.at("lambda_grid").get<std::vector<double>>();
    params.mean_lambda_grid = values.at("mean_lambda_grid").get<std::vector<double>>();
    params.fixed_direction_lambda = values.at("fixed_direction_lambda").get<double>();
    params.fixed_loading_lambda = values.at("fixed_loading_lambda").get<double>();
    params.output_dir = values.at("output_dir").get<std::string>();
    params.write_reconstructions = values.value("write_reconstructions", true);
    params.write_beta = values.value("write_beta", true);

    if (params.model_name != "R1_fPLS" && params.model_name != "fPCR") {
        throw std::runtime_error("model must be R1_fPLS or fPCR");
    }

    // functional centering is performed explicitly in main with the training-only smoothed mean
    if (values.at("center").get<bool>()) {
        throw std::runtime_error(
          "model-internal centering must stay false; the native preprocessing "
          "stage applies the GCV-smoothed functional mean explicitly");
    }
    if (
      params.n_comp < 1 || params.max_iter < 1 || params.tolerance <= 0 || params.gcv_probes < 1 ||
      params.mean_gcv_probes < 1) {
        throw std::runtime_error("invalid fPLS configuration");
    }
    params.X_file = values.at("X_file").get<std::string>();
    params.Y_file = values.at("Y_file").get<std::string>();
    params.nodes_file = values.at("nodes_file").get<std::string>();
    params.elements_file = values.at("elements_file").get<std::string>();
    params.boundary_file = values.at("boundary_file").get<std::string>();
    // fPCR may provide its own fixed lambda; otherwise preserve the loading-lambda default
    if (params.model_name == "fPCR") {
        params.fixed_fpca_lambda = values.value("fixed_fpca_lambda", params.fixed_loading_lambda);
    }
    params.provenance = values.at("provenance");
    return params;
}

#endif
