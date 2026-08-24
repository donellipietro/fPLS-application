#include <fdaPDE/models.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace fdapde;
using nlohmann::json;

using matrix_t = Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic>;
using vector_t = Eigen::Matrix<double, Eigen::Dynamic, 1>;

struct explicit_edf_fpca_fit {
  matrix_t f;
  matrix_t fn;
  matrix_t scores;
  matrix_t lambdas;
  std::vector<double> loading_norms;
  std::vector<std::vector<double>> objective_histories;
  std::vector<int> iteration_counts;
  std::vector<bool> monotonicity;

  const matrix_t &F() const { return f; }
  const matrix_t &Fn() const { return fn; }
  const matrix_t &S() const { return scores; }
  const matrix_t &lambda() const { return lambdas; }
  const std::vector<double> &loadings_norm() const { return loading_norms; }
  const std::vector<std::vector<double>> &objective_history() const {
    return objective_histories;
  }
  const std::vector<int> &iterations() const { return iteration_counts; }
  const std::vector<bool> &monotone() const { return monotonicity; }
};

struct functional_mean_fit {
  vector_t coefficients;
  vector_t locations;
  double selected_lambda;
  std::vector<double> effective_degrees_of_freedom;
  std::vector<double> gcv_scores;
};

functional_mean_fit fit_functional_mean_gcv(
    const matrix_t &X, fdapde::internals::fe_ls_elliptic &smoother,
    const std::vector<double> &lambda_grid, int gcv_probes, int gcv_seed) {
  if (lambda_grid.empty() || gcv_probes < 1 ||
      std::any_of(lambda_grid.begin(), lambda_grid.end(), [](double value) {
        return !std::isfinite(value) || value <= 0;
      })) {
    throw std::runtime_error("invalid functional-mean GCV configuration");
  }

  const vector_t empirical_mean = X.colwise().mean().transpose();
  smoother.update_response(empirical_mean);
  functional_mean_fit result;
  result.effective_degrees_of_freedom.reserve(lambda_grid.size());
  result.gcv_scores.reserve(lambda_grid.size());

  std::size_t selected = 0;
  double best_gcv = std::numeric_limits<double>::infinity();
  for (std::size_t index = 0; index < lambda_grid.size(); ++index) {
    const double lambda = lambda_grid[index];
    smoother.fit(lambda);
    const double edf = smoother.edf(lambda, gcv_probes, gcv_seed);
    const double residual_degrees_of_freedom =
        static_cast<double>(X.cols()) - edf;
    if (!std::isfinite(edf) || residual_degrees_of_freedom <= 0) {
      throw std::runtime_error(
          "functional-mean GCV has invalid residual degrees of freedom");
    }
    const double gcv =
        (static_cast<double>(X.cols()) /
         std::pow(residual_degrees_of_freedom, 2)) *
        (smoother.fn() - empirical_mean).squaredNorm();
    if (!std::isfinite(gcv))
      throw std::runtime_error("functional-mean GCV score is non-finite");
    result.effective_degrees_of_freedom.push_back(edf);
    result.gcv_scores.push_back(gcv);
    if (gcv < best_gcv) {
      best_gcv = gcv;
      selected = index;
    }
  }

  result.selected_lambda = lambda_grid[selected];
  smoother.fit(result.selected_lambda);
  result.coefficients = smoother.f();
  result.locations = smoother.fn();
  if (!result.coefficients.allFinite() || !result.locations.allFinite())
    throw std::runtime_error("functional-mean fit is non-finite");
  return result;
}

template <typename Model>
matrix_t fpls_loading_gcv_diagnostics(
    const matrix_t &X, const Model &model,
    fdapde::internals::fe_ls_elliptic &smoother,
    const std::vector<double> &lambda_grid, const matrix_t &selected_lambdas,
    int gcv_probes, int gcv_seed) {
  const int n_comp = model.X_latent_scores().cols();
  matrix_t diagnostics(n_comp * lambda_grid.size(), 5);
  matrix_t residual = X;
  for (int h = 0; h < n_comp; ++h) {
    const vector_t score = model.X_latent_scores().col(h);
    const double score_norm = score.squaredNorm();
    if (!std::isfinite(score_norm) || score_norm <= 0)
      throw std::runtime_error("invalid fPLS score in loading GCV replay");
    const vector_t response = residual.transpose() * score / score_norm;
    smoother.update_response(response);

    std::size_t selected = 0;
    double best_gcv = std::numeric_limits<double>::infinity();
    for (std::size_t index = 0; index < lambda_grid.size(); ++index) {
      const double lambda = lambda_grid[index];
      smoother.fit(lambda);
      const double edf = smoother.edf(lambda, gcv_probes, gcv_seed);
      const double residual_degrees_of_freedom = X.cols() - edf;
      if (!std::isfinite(edf) || residual_degrees_of_freedom <= 0)
        throw std::runtime_error("invalid fPLS loading GCV replay EDF");
      const double gcv =
          (X.cols() / std::pow(residual_degrees_of_freedom, 2)) *
          (smoother.fn() - response).squaredNorm();
      if (!std::isfinite(gcv))
        throw std::runtime_error("non-finite fPLS loading GCV replay score");
      const Eigen::Index row = h * lambda_grid.size() + index;
      diagnostics.row(row) << h + 1, lambda, edf, gcv, 0;
      if (gcv < best_gcv) {
        best_gcv = gcv;
        selected = index;
      }
    }
    diagnostics(h * lambda_grid.size() + selected, 4) = 1;
    if (lambda_grid[selected] != selected_lambdas(h, 0))
      throw std::runtime_error(
          "fPLS loading GCV replay does not match the fitted model");
    residual.noalias() -=
        score * (smoother.Psi() * model.X_loadings().col(h)).transpose();
  }
  return diagnostics;
}

explicit_edf_fpca_fit fit_fpca_explicit_edf(
    const matrix_t &X, fdapde::internals::fe_ls_elliptic &smoother, int n_comp,
    const std::vector<double> &lambda_grid, const std::string &calibration,
    double fixed_lambda, int max_iter, double tolerance, int gcv_probes,
    int gcv_seed) {
  if (!X.allFinite() || n_comp < 1 || n_comp > std::min(X.rows(), X.cols())) {
    throw std::runtime_error("invalid fPCA data or component count");
  }

  struct component_fit {
    vector_t f;
    vector_t score;
    std::vector<double> objective_history;
    int iterations = 0;
    bool monotone = true;
  };

  const Eigen::JacobiSVD<matrix_t> svd(X, Eigen::ComputeThinU |
                                              Eigen::ComputeThinV);
  const matrix_t initial_loadings = svd.matrixV();
  matrix_t residual = X;
  std::vector<std::pair<double, double>> edf_cache;

  explicit_edf_fpca_fit result;
  result.f.resize(smoother.n_dofs(), n_comp);
  result.fn.resize(X.cols(), n_comp);
  result.scores.resize(X.rows(), n_comp);
  result.lambdas.resize(n_comp, 1);
  result.loading_norms.resize(n_comp);
  result.objective_histories.resize(n_comp);
  result.iteration_counts.resize(n_comp);
  result.monotonicity.resize(n_comp);

  auto solve_component = [&](const auto &lambda,
                             const vector_t &initial_loading) {
    vector_t sampled_loading = initial_loading;
    vector_t score(X.rows());
    double previous_objective = std::numeric_limits<double>::max();
    double objective = 1.0;
    component_fit fit;
    fit.objective_history.reserve(max_iter);

    while (!almost_equal(objective, previous_objective, tolerance) &&
           fit.iterations < max_iter) {
      score.noalias() = residual * sampled_loading;
      const double score_norm = score.norm();
      if (!score.allFinite() || !std::isfinite(score_norm) || score_norm <= 0) {
        throw std::runtime_error(
            "fPCA score update is non-finite or numerically singular");
      }
      score /= score_norm;

      const vector_t response = residual.transpose() * score;
      if (!response.allFinite()) {
        throw std::runtime_error("fPCA smoother response is non-finite");
      }
      smoother.update_response(response);
      smoother.fit(lambda);
      sampled_loading = smoother.fn();
      if (!sampled_loading.allFinite() || !smoother.f().allFinite()) {
        throw std::runtime_error(
            "fPCA smoother produced a non-finite solution");
      }

      ++fit.iterations;
      previous_objective = objective;
      objective =
          (residual - score * sampled_loading.transpose()).squaredNorm() +
          smoother.ftPf(lambda);
      if (!std::isfinite(objective)) {
        throw std::runtime_error("fPCA objective is non-finite");
      }
      fit.objective_history.push_back(objective);
      if (fit.iterations > 1 && (objective - previous_objective) /
                                        (1.0 + std::abs(previous_objective)) >
                                    tolerance) {
        fit.monotone = false;
      }
    }

    fit.f = smoother.f();
    fit.score = std::move(score);
    return fit;
  };

  auto explicit_edf = [&](const auto &lambda) {
    const double key = lambda[0];
    const auto cached =
        std::find_if(edf_cache.begin(), edf_cache.end(),
                     [key](const auto &entry) { return entry.first == key; });
    if (cached != edf_cache.end())
      return cached->second;
    const double value = smoother.edf(lambda, gcv_probes, gcv_seed);
    if (!std::isfinite(value))
      throw std::runtime_error(
          "fPCA effective degrees of freedom is non-finite");
    edf_cache.emplace_back(key, value);
    return value;
  };

  for (int h = 0; h < n_comp; ++h) {
    Eigen::Matrix<double, 1, 1> selected_lambda;
    if (calibration == "gcv") {
      auto gcv = [&](const auto &lambda) -> double {
        const component_fit candidate =
            solve_component(lambda, initial_loadings.col(h));
        const double residual_degrees_of_freedom =
            static_cast<double>(X.cols()) - explicit_edf(lambda);
        if (!std::isfinite(residual_degrees_of_freedom) ||
            residual_degrees_of_freedom <= 0) {
          throw std::runtime_error(
              "fPCA GCV has no positive residual degrees of freedom");
        }
        const double value =
            (static_cast<double>(X.cols()) /
             std::pow(residual_degrees_of_freedom, 2)) *
            ((smoother.Psi() * candidate.f) - smoother.response())
                .squaredNorm();
        if (!std::isfinite(value))
          throw std::runtime_error("fPCA GCV score is non-finite");
        return value;
      };
      GridSearch<1> optimizer;
      selected_lambda = optimizer.optimize(gcv, lambda_grid);
    } else {
      selected_lambda << fixed_lambda;
    }

    component_fit component =
        solve_component(selected_lambda, initial_loadings.col(h));
    const double loading_norm =
        std::sqrt(component.f.dot(smoother.mass() * component.f));
    if (!std::isfinite(loading_norm) || loading_norm <= 0) {
      throw std::runtime_error("invalid fPCA functional loading norm");
    }

    result.loading_norms[h] = loading_norm;
    result.f.col(h) = component.f / loading_norm;
    result.fn.col(h) = smoother.Psi() * result.f.col(h);
    result.scores.col(h) = component.score * loading_norm;
    result.lambdas(h, 0) = selected_lambda[0];
    result.objective_histories[h] = std::move(component.objective_history);
    result.iteration_counts[h] = component.iterations;
    result.monotonicity[h] = component.monotone;
    residual.noalias() -= result.scores.col(h) * result.fn.col(h).transpose();
  }

  return result;
}

matrix_t read_matrix(const std::string &file) {
  const std::filesystem::path path(file);
  const std::string readable_path =
      path.is_absolute()
          ? std::filesystem::relative(path, std::filesystem::current_path())
                .string()
          : file;
  return read_csv<double>(readable_path, true, false).as_matrix();
}

std::string output_file(const std::filesystem::path &output_dir,
                        const std::string &name) {
  return (output_dir / name).string();
}

int run_application(const json &params) {
  const auto wall_start = std::chrono::steady_clock::now();

  const std::string model_name = params.at("model").get<std::string>();
  const int n_comp = params.at("n_comp").get<int>();
  const int max_iter = params.at("max_iter").get<int>();
  const double tolerance = params.at("tolerance").get<double>();
  const int gcv_probes = params.at("gcv_probes").get<int>();
  const int gcv_seed = params.at("gcv_seed").get<int>();
  const int mean_gcv_probes = params.at("mean_gcv_probes").get<int>();
  const int mean_gcv_seed = params.at("mean_gcv_seed").get<int>();
  const std::string calibration = params.at("calibration").get<std::string>();
  const std::vector<double> lambda_grid =
      params.at("lambda_grid").get<std::vector<double>>();
  const std::vector<double> mean_lambda_grid =
      params.at("mean_lambda_grid").get<std::vector<double>>();
  const double fixed_direction_lambda =
      params.at("fixed_direction_lambda").get<double>();
  const double fixed_loading_lambda =
      params.at("fixed_loading_lambda").get<double>();
  const std::filesystem::path output_dir(
      params.at("output_dir").get<std::string>());
  const bool write_reconstructions =
      params.value("write_reconstructions", true);
  const bool write_beta = params.value("write_beta", true);

  if (model_name != "R1_fPLS" && model_name != "fPCR") {
    throw std::runtime_error("model must be R1_fPLS or fPCR");
  }

  if (params.at("center").get<bool>()) {
    throw std::runtime_error(
        "model-internal centering must stay false; the native preprocessing "
        "stage applies the GCV-smoothed functional mean explicitly");
  }
  if (n_comp < 1 || max_iter < 1 || tolerance <= 0 || gcv_probes < 1 ||
      mean_gcv_probes < 1) {
    throw std::runtime_error("invalid fPLS configuration");
  }

  const matrix_t X_raw = read_matrix(params.at("X_file").get<std::string>());
  const matrix_t Y = read_matrix(params.at("Y_file").get<std::string>());
  const matrix_t nodes =
      read_matrix(params.at("nodes_file").get<std::string>());
  const matrix_t elements_source =
      read_matrix(params.at("elements_file").get<std::string>());
  const matrix_t boundary_source =
      read_matrix(params.at("boundary_file").get<std::string>());
  std::cout << "- Loaded brain data: " << X_raw.rows() << " subjects, "
            << X_raw.cols() << " mesh nodes" << std::endl;
  if (nodes.cols() != 3 || elements_source.cols() != 4 ||
      boundary_source.cols() != 1) {
    throw std::runtime_error("invalid 3D mesh input dimensions");
  }
  if (X_raw.rows() != Y.rows() || X_raw.cols() != nodes.rows()) {
    throw std::runtime_error("X, Y, and mesh-node dimensions do not agree");
  }

  Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> elements =
      elements_source.cast<int>();
  Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> boundary =
      boundary_source.cast<int>();
  std::cout << "- Building tetrahedral FEM space: " << elements.rows()
            << " elements" << std::endl;
  Triangulation<3, 3> domain(nodes, elements, boundary, cache_cells);
  FeSpace space(domain, P1<1>);
  TrialFunction f(space);
  TestFunction v(space);
  const auto penalty = integral(domain)(dot(grad(f), grad(v)));
  ZeroField<3> forcing;
  const auto load = integral(domain)(forcing * v);
  GeoFrame data(domain);
  auto &layer =
      data.template insert_scalar_layer<POINT>("observations", MESH_NODES);

  const auto centering_start = std::chrono::steady_clock::now();
  auto mean_penalty = fe_ls_elliptic(penalty, load);
  fdapde::internals::fe_ls_elliptic mean_smoother;
  mean_smoother.discretize(mean_penalty.get());
  mean_smoother.analyze_data(
      data, vector_t::Ones(data[0].rows()).asDiagonal());
  std::cout << "- Fitting training-only functional mean by GCV over "
            << mean_lambda_grid.size() << " candidate lambda(s)" << std::endl;
  const functional_mean_fit mean_fit = fit_functional_mean_gcv(
      X_raw, mean_smoother, mean_lambda_grid, mean_gcv_probes, mean_gcv_seed);
  const matrix_t X = X_raw.rowwise() - mean_fit.locations.transpose();
  if (!X.allFinite())
    throw std::runtime_error("functional-mean centered data are non-finite");
  layer.load_blk("X", X.transpose());
  const auto centering_end = std::chrono::steady_clock::now();
  std::cout << "- Functional mean completed: lambda="
            << mean_fit.selected_lambda << std::endl;

  std::filesystem::create_directories(output_dir);
  write_csv(output_file(output_dir, "functional_mean_coefficients.csv"),
            mean_fit.coefficients);
  write_csv(output_file(output_dir, "functional_mean_locations.csv"),
            mean_fit.locations);
  matrix_t mean_gcv_diagnostics(mean_lambda_grid.size(), 3);
  for (std::size_t index = 0; index < mean_lambda_grid.size(); ++index) {
    mean_gcv_diagnostics(index, 0) = mean_lambda_grid[index];
    mean_gcv_diagnostics(index, 1) =
        mean_fit.effective_degrees_of_freedom[index];
    mean_gcv_diagnostics(index, 2) = mean_fit.gcv_scores[index];
  }
  write_csv(output_file(output_dir, "functional_mean_gcv.csv"),
            mean_gcv_diagnostics,
            std::vector<std::string>{"lambda", "edf", "gcv"});

  if (model_name == "R1_fPLS") {
    auto direction_penalty = fe_ls_elliptic(penalty, load);
    auto loading_penalty = fe_ls_elliptic(penalty, load);
    fPLS model("X", Y, data, std::move(direction_penalty),
               std::move(loading_penalty));
    const auto setup_end = std::chrono::steady_clock::now();

    matrix_t direction_lambdas;
    matrix_t loading_lambdas;
    matrix_t loading_gcv_diagnostics;
    std::cout << "Starting fPLS fit: H=" << n_comp
              << ", calibration=" << calibration;
    if (calibration == "gcv")
      std::cout << ", " << lambda_grid.size() << " candidate lambdas";
    std::cout << std::endl;
    if (calibration == "gcv") {
      if (lambda_grid.empty())
        throw std::runtime_error("empty GCV lambda grid");
      model.fit(n_comp, lambda_grid, lambda_grid, OptimizeGCV, max_iter,
                tolerance, gcv_probes, gcv_seed);
      direction_lambdas = model.direction_lambda();
      loading_lambdas = model.loading_lambda();
      auto diagnostic_penalty = fe_ls_elliptic(penalty, load);
      fdapde::internals::fe_ls_elliptic diagnostic_smoother;
      diagnostic_smoother.discretize(diagnostic_penalty.get());
      diagnostic_smoother.analyze_data(
          data, vector_t::Ones(data[0].rows()).asDiagonal());
      loading_gcv_diagnostics = fpls_loading_gcv_diagnostics(
          X, model, diagnostic_smoother, lambda_grid, loading_lambdas,
          gcv_probes, gcv_seed);
    } else if (calibration == "fixed") {
      Eigen::Matrix<double, 1, 1> direction_lambda;
      Eigen::Matrix<double, 1, 1> loading_lambda;
      direction_lambda << fixed_direction_lambda;
      loading_lambda << fixed_loading_lambda;
      model.fit(n_comp, direction_lambda, loading_lambda, max_iter, tolerance);
      direction_lambdas = matrix_t::Constant(n_comp, 1, fixed_direction_lambda);
      loading_lambdas = matrix_t::Constant(n_comp, 1, fixed_loading_lambda);
    } else {
      throw std::runtime_error("calibration must be gcv or fixed");
    }
    const auto fit_end = std::chrono::steady_clock::now();

    write_csv(output_file(output_dir, "x_space_directions_coefficients.csv"),
              model.X_space_directions());
    write_csv(output_file(output_dir, "y_space_directions.csv"),
              model.Y_space_directions());
    write_csv(output_file(output_dir, "x_latent_scores.csv"),
              model.X_latent_scores());
    write_csv(output_file(output_dir, "y_latent_scores.csv"),
              model.Y_latent_scores());
    write_csv(output_file(output_dir, "x_loadings_coefficients.csv"),
              model.X_loadings());
    write_csv(output_file(output_dir, "y_loadings.csv"), model.Y_loadings());
    write_csv(output_file(output_dir, "direction_lambdas.csv"),
              direction_lambdas);
    write_csv(output_file(output_dir, "loading_lambdas.csv"), loading_lambdas);
    if (calibration == "gcv") {
      write_csv(output_file(output_dir, "fpls_loading_gcv.csv"),
                loading_gcv_diagnostics,
                std::vector<std::string>{"component", "lambda", "edf", "gcv",
                                         "selected"});
    }
    matrix_t component_diagnostics(n_comp, 6);
    for (int h = 0; h < n_comp; ++h) {
      const auto &history = model.direction_objective_history()[h];
      Eigen::Map<const matrix_t> history_matrix(history.data(), history.size(),
                                                1);
      write_csv(output_file(output_dir, "objective_history_h" +
                                            std::to_string(h + 1) + ".csv"),
                history_matrix);
      component_diagnostics(h, 0) = h + 1;
      component_diagnostics(h, 1) = model.direction_iterations()[h];
      component_diagnostics(h, 2) = model.direction_monotone()[h] ? 1.0 : 0.0;
      component_diagnostics(h, 3) =
          history.empty() ? std::numeric_limits<double>::quiet_NaN()
                          : history.back();
      component_diagnostics(h, 4) =
          model.direction_iterations()[h] >= max_iter ? 1.0 : 0.0;
      component_diagnostics(h, 5) =
          !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;
      std::cout << "- Component " << h + 1 << '/' << n_comp
                << " completed: direction lambda=" << direction_lambdas(h, 0)
                << ", iterations=" << model.direction_iterations()[h]
                << std::endl;
    }
    write_csv(output_file(output_dir, "component_diagnostics.csv"),
              component_diagnostics,
              std::vector<std::string>{"component", "iterations", "monotone",
                                       "objective", "hit_max_iter",
                                       "finite_solution"});

    json component_files = json::array();
    for (int h = 1; h <= n_comp; ++h) {
      const std::string suffix = "_h" + std::to_string(h) + ".csv";
      write_csv(output_file(output_dir, "y_hat" + suffix), model.fitted(h));
      json files{{"component", h}, {"y_hat", "y_hat" + suffix}};
      if (write_reconstructions) {
        write_csv(output_file(output_dir, "x_hat_locations" + suffix),
                  model.reconstructed(h));
        files["x_hat_locations"] = "x_hat_locations" + suffix;
      }
      if (write_beta) {
        write_csv(output_file(output_dir, "beta_coefficients" + suffix),
                  model.Beta(h));
        files["beta_coefficients"] = "beta_coefficients" + suffix;
      }
      component_files.push_back(std::move(files));
    }
    const auto output_end = std::chrono::steady_clock::now();

    const double setup_seconds =
        std::chrono::duration<double>(setup_end - wall_start).count();
    const double fit_seconds =
        std::chrono::duration<double>(fit_end - setup_end).count();
    const double output_seconds =
        std::chrono::duration<double>(output_end - fit_end).count();
    const double wall_seconds =
        std::chrono::duration<double>(output_end - wall_start).count();
    std::vector<int> monotone;
    monotone.reserve(model.direction_monotone().size());
    for (bool value : model.direction_monotone())
      monotone.push_back(value ? 1 : 0);

    json telemetry_json;
    telemetry_json["schema_version"] = 3;
    telemetry_json["model"] = "R1_fPLS";
    telemetry_json["mode"] = "native_fdaPDE_cpp";
    telemetry_json["discretization"] = "tetrahedral_fem";
    telemetry_json["center"] = false;
    telemetry_json["centering"] =
        "training_overall_gcv_smoothed_functional_mean";
    telemetry_json["mean_lambda_grid"] = mean_lambda_grid;
    telemetry_json["mean_gcv_probes"] = mean_gcv_probes;
    telemetry_json["mean_gcv_seed"] = mean_gcv_seed;
    telemetry_json["mean_selected_lambda"] = mean_fit.selected_lambda;
    telemetry_json["mean_effective_degrees_of_freedom"] =
        mean_fit.effective_degrees_of_freedom;
    telemetry_json["mean_gcv_scores"] = mean_fit.gcv_scores;
    telemetry_json["mean_formula"] =
        "argmin_lambda m/(m-edf_lambda)^2*||S_lambda*colMeans(X_train)-"
        "colMeans(X_train)||_2^2";
    telemetry_json["mean_scope"] = "native_fit_training_rows_only";
    telemetry_json["calibration"] = calibration;
    telemetry_json["fit_includes_gcv"] = calibration == "gcv";
    telemetry_json["write_reconstructions"] = write_reconstructions;
    telemetry_json["write_beta"] = write_beta;
    telemetry_json["n_units"] = X.rows();
    telemetry_json["n_locations"] = X.cols();
    telemetry_json["n_responses"] = Y.cols();
    telemetry_json["n_components"] = n_comp;
    telemetry_json["n_basis"] = space.n_dofs();
    telemetry_json["max_iter"] = max_iter;
    telemetry_json["tolerance"] = tolerance;
    telemetry_json["gcv_probes"] = gcv_probes;
    telemetry_json["gcv_seed"] = gcv_seed;
    telemetry_json["lambda_grid"] = lambda_grid;
    telemetry_json["fpls_loading_gcv_file"] =
        calibration == "gcv" ? "fpls_loading_gcv.csv" : "not_applicable";
    telemetry_json["fpls_loading_gcv_replay_matches_fit"] =
        calibration == "gcv";
    telemetry_json["fixed_direction_lambda"] = fixed_direction_lambda;
    telemetry_json["fixed_loading_lambda"] = fixed_loading_lambda;
    telemetry_json["setup_seconds"] = setup_seconds;
    telemetry_json["centering_seconds"] =
        std::chrono::duration<double>(centering_end - centering_start).count();
    telemetry_json["fit_seconds"] = fit_seconds;
    telemetry_json["output_seconds"] = output_seconds;
    telemetry_json["wall_seconds"] = wall_seconds;
    telemetry_json["iteration_counts_available"] = true;
    telemetry_json["iteration_counts"] = model.direction_iterations();
    telemetry_json["monotone"] = monotone;
    telemetry_json["component_files"] = component_files;
    telemetry_json["provenance"] = params.at("provenance");
    std::ofstream telemetry(output_file(output_dir, "telemetry.json"));
    telemetry << telemetry_json.dump(2) << '\n';

    std::cout << "fPLS fit completed." << std::endl;

    return 0;
  }

  if (Y.cols() != 1)
    throw std::runtime_error("fPCR currently requires a scalar response");

  const auto fpca_penalty = fe_ls_elliptic(penalty, load);
  fdapde::internals::fe_ls_elliptic fpca_smoother;
  fpca_smoother.discretize(fpca_penalty.get());
  fpca_smoother.analyze_data(data, vector_t::Ones(data[0].rows()).asDiagonal());
  const auto setup_end = std::chrono::steady_clock::now();
  const double fixed_fpca_lambda =
      params.value("fixed_fpca_lambda", fixed_loading_lambda);

  std::cout << "Starting fPCR fit: H=" << n_comp
            << ", calibration=" << calibration;
  if (calibration == "gcv")
    std::cout << ", " << lambda_grid.size() << " candidate lambdas";
  std::cout << std::endl;
  if (calibration == "gcv") {
    if (lambda_grid.empty())
      throw std::runtime_error("empty fPCA GCV lambda grid");
    if (gcv_seed == random_seed) {
      throw std::runtime_error(
          "fPCA GCV requires an explicit deterministic seed");
    }
  } else if (calibration != "fixed") {
    throw std::runtime_error("calibration must be gcv or fixed");
  }
  if ((calibration == "fixed" &&
       (!std::isfinite(fixed_fpca_lambda) || fixed_fpca_lambda <= 0)) ||
      (calibration == "gcv" &&
       std::any_of(lambda_grid.begin(), lambda_grid.end(), [](double value) {
         return !std::isfinite(value) || value <= 0;
       }))) {
    throw std::runtime_error(
        "fPCA smoothing parameters must be finite and positive");
  }
  const explicit_edf_fpca_fit model = fit_fpca_explicit_edf(
      X, fpca_smoother, n_comp, lambda_grid, calibration, fixed_fpca_lambda,
      max_iter, tolerance, gcv_probes, gcv_seed);
  const auto fit_end = std::chrono::steady_clock::now();

  const matrix_t sampled_loadings = model.Fn();
  if (sampled_loadings.rows() != X.cols() ||
      sampled_loadings.cols() != n_comp) {
    throw std::runtime_error("fPCA loadings do not match the training data");
  }

  matrix_t scores(X.rows(), n_comp);
  matrix_t directions(model.F().rows(), n_comp);
  matrix_t sampled_directions(X.cols(), n_comp);
  matrix_t projection_scales(n_comp, 1);
  matrix_t residual = X;
  std::vector<double> projection_errors(n_comp);
  for (int h = 0; h < n_comp; ++h) {
    const matrix_t raw_score = residual * sampled_loadings.col(h);
    const double denominator = raw_score.norm();
    const double loading_norm = model.loadings_norm()[h];
    if (!std::isfinite(denominator) || denominator <= 0 ||
        !std::isfinite(loading_norm) || loading_norm <= 0) {
      throw std::runtime_error("invalid fPCA score projection scale");
    }
    const double alpha = loading_norm / denominator;
    projection_scales(h, 0) = alpha;
    directions.col(h) = alpha * model.F().col(h);
    sampled_directions.col(h) = alpha * sampled_loadings.col(h);
    scores.col(h) = raw_score * alpha;
    projection_errors[h] =
        (scores.col(h) - model.S().col(h)).cwiseAbs().maxCoeff();
    residual.noalias() -= scores.col(h) * sampled_loadings.col(h).transpose();
  }

  if (!scores.allFinite() || !directions.allFinite()) {
    throw std::runtime_error("non-finite fPCR score projection");
  }

  write_csv(output_file(output_dir, "x_space_directions_coefficients.csv"),
            directions);
  write_csv(output_file(output_dir, "x_latent_scores.csv"), scores);
  write_csv(output_file(output_dir, "x_loadings_coefficients.csv"), model.F());
  write_csv(output_file(output_dir, "score_projection_scales.csv"),
            projection_scales);

  matrix_t fpca_lambdas(n_comp, 1);
  for (int h = 0; h < n_comp; ++h) {
    fpca_lambdas(h, 0) = model.lambda().rows() == n_comp ? model.lambda()(h, 0)
                                                         : model.lambda()(0, h);
  }
  write_csv(output_file(output_dir, "fpca_lambdas.csv"), fpca_lambdas);
  const matrix_t unavailable_lambdas =
      matrix_t::Constant(n_comp, 1, std::numeric_limits<double>::quiet_NaN());
  write_csv(output_file(output_dir, "direction_lambdas.csv"),
            unavailable_lambdas);
  write_csv(output_file(output_dir, "loading_lambdas.csv"),
            unavailable_lambdas);

  matrix_t component_diagnostics(n_comp, 6);
  const auto &objective_histories = model.objective_history();
  for (int h = 0; h < n_comp; ++h) {
    const auto &history = objective_histories[h];
    Eigen::Map<const matrix_t> history_matrix(history.data(), history.size(),
                                              1);
    write_csv(output_file(output_dir, "objective_history_h" +
                                          std::to_string(h + 1) + ".csv"),
              history_matrix);
    component_diagnostics(h, 0) = h + 1;
    component_diagnostics(h, 1) = model.iterations()[h];
    component_diagnostics(h, 2) = model.monotone()[h] ? 1.0 : 0.0;
    component_diagnostics(h, 3) = history.empty()
                                      ? std::numeric_limits<double>::quiet_NaN()
                                      : history.back();
    component_diagnostics(h, 4) = model.iterations()[h] >= max_iter ? 1.0 : 0.0;
    component_diagnostics(h, 5) =
        model.F().col(h).allFinite() && scores.col(h).allFinite() &&
                (history.empty() || std::isfinite(history.back()))
            ? 1.0
            : 0.0;
    std::cout << "- Component " << h + 1 << '/' << n_comp
              << " completed: fPCA lambda=" << fpca_lambdas(h, 0)
              << ", iterations=" << model.iterations()[h] << std::endl;
  }
  write_csv(output_file(output_dir, "component_diagnostics.csv"),
            component_diagnostics,
            std::vector<std::string>{"component", "iterations", "monotone",
                                     "objective", "hit_max_iter",
                                     "finite_solution"});

  matrix_t full_coefficients;
  matrix_t y_latent_scores(X.rows(), n_comp);
  json component_files = json::array();
  for (int h = 1; h <= n_comp; ++h) {
    const matrix_t scores_h = scores.leftCols(h);
    const matrix_t coefficients = scores_h.colPivHouseholderQr().solve(Y);
    const matrix_t y_hat = scores_h * coefficients;
    const std::string suffix = "_h" + std::to_string(h) + ".csv";
    write_csv(output_file(output_dir, "y_hat" + suffix), y_hat);
    json files{{"component", h}, {"y_hat", "y_hat" + suffix}};

    if (write_reconstructions) {
      write_csv(output_file(output_dir, "x_hat_locations" + suffix),
                scores_h * sampled_loadings.leftCols(h).transpose());
      files["x_hat_locations"] = "x_hat_locations" + suffix;
    }
    if (write_beta) {
      const matrix_t cross_loadings = sampled_loadings.leftCols(h).transpose() *
                                      sampled_directions.leftCols(h);
      matrix_t projection_transform = matrix_t::Identity(h, h);
      projection_transform.triangularView<Eigen::StrictlyUpper>() =
          cross_loadings.triangularView<Eigen::StrictlyUpper>();
      const matrix_t transformed_coefficients =
          projection_transform.triangularView<Eigen::Upper>().solve(
              coefficients);
      const matrix_t beta = directions.leftCols(h) * transformed_coefficients;
      const matrix_t sampled_beta =
          sampled_directions.leftCols(h) * transformed_coefficients;
      const double beta_projection_error =
          (X * sampled_beta - y_hat).cwiseAbs().maxCoeff();
      if (!std::isfinite(beta_projection_error) ||
          beta_projection_error > 1e-8 * (1.0 + y_hat.cwiseAbs().maxCoeff())) {
        throw std::runtime_error(
            "fPCR coefficient does not reproduce the sequential prediction");
      }
      write_csv(output_file(output_dir, "beta_coefficients" + suffix), beta);
      files["beta_coefficients"] = "beta_coefficients" + suffix;
    }
    component_files.push_back(std::move(files));
    if (h == n_comp)
      full_coefficients = coefficients;
  }

  for (int h = 0; h < n_comp; ++h) {
    y_latent_scores.col(h) = scores.col(h) * full_coefficients(h, 0);
  }
  write_csv(output_file(output_dir, "y_space_directions.csv"),
            full_coefficients.transpose());
  write_csv(output_file(output_dir, "y_loadings.csv"),
            full_coefficients.transpose());
  write_csv(output_file(output_dir, "y_latent_scores.csv"), y_latent_scores);

  const auto output_end = std::chrono::steady_clock::now();
  const double setup_seconds =
      std::chrono::duration<double>(setup_end - wall_start).count();
  const double fit_seconds =
      std::chrono::duration<double>(fit_end - setup_end).count();
  const double output_seconds =
      std::chrono::duration<double>(output_end - fit_end).count();
  const double wall_seconds =
      std::chrono::duration<double>(output_end - wall_start).count();
  std::vector<int> monotone;
  monotone.reserve(model.monotone().size());
  for (bool value : model.monotone())
    monotone.push_back(value ? 1 : 0);

  json telemetry_json;
  telemetry_json["schema_version"] = 3;
  telemetry_json["model"] = "fPCR";
  telemetry_json["mode"] = "native_fdaPDE_cpp";
  telemetry_json["discretization"] = "tetrahedral_fem";
  telemetry_json["fpca_solver"] = "power_iteration";
  telemetry_json["fpca_initialization"] = "exact_svd";
  telemetry_json["fpca_implementation"] =
      "application_local_with_explicit_edf_control";
  telemetry_json["fpca_gcv_edf"] =
      json{{"applied", calibration == "gcv"},
           {"method", "hutchinson"},
           {"probe_count_source", "gcv_probes"},
           {"seed_source", "gcv_seed"},
           {"seed_mode", "explicit_deterministic"},
           {"cache", "per_lambda_shared_across_components"}};
  telemetry_json["center"] = false;
  telemetry_json["centering"] =
      "training_overall_gcv_smoothed_functional_mean";
  telemetry_json["mean_lambda_grid"] = mean_lambda_grid;
  telemetry_json["mean_gcv_probes"] = mean_gcv_probes;
  telemetry_json["mean_gcv_seed"] = mean_gcv_seed;
  telemetry_json["mean_selected_lambda"] = mean_fit.selected_lambda;
  telemetry_json["mean_effective_degrees_of_freedom"] =
      mean_fit.effective_degrees_of_freedom;
  telemetry_json["mean_gcv_scores"] = mean_fit.gcv_scores;
  telemetry_json["mean_formula"] =
      "argmin_lambda m/(m-edf_lambda)^2*||S_lambda*colMeans(X_train)-"
      "colMeans(X_train)||_2^2";
  telemetry_json["mean_scope"] = "native_fit_training_rows_only";
  telemetry_json["calibration"] = calibration;
  telemetry_json["fit_includes_gcv"] = calibration == "gcv";
  telemetry_json["write_reconstructions"] = write_reconstructions;
  telemetry_json["write_beta"] = write_beta;
  telemetry_json["n_units"] = X.rows();
  telemetry_json["n_locations"] = X.cols();
  telemetry_json["n_responses"] = Y.cols();
  telemetry_json["n_components"] = n_comp;
  telemetry_json["n_basis"] = space.n_dofs();
  telemetry_json["max_iter"] = max_iter;
  telemetry_json["tolerance"] = tolerance;
  telemetry_json["gcv_probes"] = gcv_probes;
  telemetry_json["gcv_seed"] = gcv_seed;
  telemetry_json["lambda_grid"] = lambda_grid;
  telemetry_json["fixed_fpca_lambda"] = fixed_fpca_lambda;
  telemetry_json["fpca_lambdas"] =
      std::vector<double>(fpca_lambdas.data(), fpca_lambdas.data() + n_comp);
  telemetry_json["score_projection_scales"] = std::vector<double>(
      projection_scales.data(), projection_scales.data() + n_comp);
  telemetry_json["score_projection_reference"] = "model.S()";
  telemetry_json["score_projection_component_max_abs_error"] =
      projection_errors;
  telemetry_json["score_projection_max_abs_error"] =
      *std::max_element(projection_errors.begin(), projection_errors.end());
  telemetry_json["score_projection_definition"] =
      "sequential_residual_times_alpha_F_with_alpha_loading_norm_over_raw_"
      "score_norm";
  telemetry_json["regression"] =
      "training_only_OLS_refit_for_each_component_prefix";
  telemetry_json["setup_seconds"] = setup_seconds;
  telemetry_json["centering_seconds"] =
      std::chrono::duration<double>(centering_end - centering_start).count();
  telemetry_json["fit_seconds"] = fit_seconds;
  telemetry_json["output_seconds"] = output_seconds;
  telemetry_json["wall_seconds"] = wall_seconds;
  telemetry_json["iteration_counts_available"] = true;
  telemetry_json["iteration_counts"] = model.iterations();
  telemetry_json["monotone"] = monotone;
  telemetry_json["component_files"] = component_files;
  telemetry_json["provenance"] = params.at("provenance");
  std::ofstream telemetry(output_file(output_dir, "telemetry.json"));
  telemetry << telemetry_json.dump(2) << '\n';

  std::cout << "fPCR fit completed." << std::endl;
  return 0;
}

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <params.json>\n";
      return 1;
    }
    std::ifstream input(argv[1]);
    if (!input)
      throw std::runtime_error("cannot open parameter file");
    return run_application(json::parse(input));
  } catch (const std::exception &error) {
    std::cerr << "brain application failed: " << error.what() << '\n';
    return 2;
  }
}
