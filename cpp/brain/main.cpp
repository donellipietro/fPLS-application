#include <fdaPDE/models.h>
#include <nlohmann/json.hpp>

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

matrix_t read_matrix(const std::string& file) {
    const std::filesystem::path path(file);
    const std::string readable_path = path.is_absolute() ?
      std::filesystem::relative(path, std::filesystem::current_path()).string() : file;
    return read_csv<double>(readable_path, true, false).as_matrix();
}

std::string output_file(const std::filesystem::path& output_dir, const std::string& name) {
    return (output_dir / name).string();
}

int run_application(const json& params) {
    const auto wall_start = std::chrono::steady_clock::now();

    const int n_comp = params.at("n_comp").get<int>();
    const int max_iter = params.at("max_iter").get<int>();
    const double tolerance = params.at("tolerance").get<double>();
    const int gcv_probes = params.at("gcv_probes").get<int>();
    const int gcv_seed = params.at("gcv_seed").get<int>();
    const std::string calibration = params.at("calibration").get<std::string>();
    const std::vector<double> lambda_grid = params.at("lambda_grid").get<std::vector<double>>();
    const double fixed_direction_lambda = params.at("fixed_direction_lambda").get<double>();
    const double fixed_loading_lambda = params.at("fixed_loading_lambda").get<double>();
    const std::filesystem::path output_dir(params.at("output_dir").get<std::string>());
    const bool write_reconstructions = params.value("write_reconstructions", true);
    const bool write_beta = params.value("write_beta", true);

    if (params.at("center").get<bool>()) {
        throw std::runtime_error("R-side overall centering is required; native centering must stay false");
    }
    if (n_comp < 1 || max_iter < 1 || tolerance <= 0 || gcv_probes < 1) {
        throw std::runtime_error("invalid fPLS configuration");
    }

    const matrix_t X = read_matrix(params.at("X_file").get<std::string>());
    const matrix_t Y = read_matrix(params.at("Y_file").get<std::string>());
    const matrix_t nodes = read_matrix(params.at("nodes_file").get<std::string>());
    const matrix_t elements_source = read_matrix(params.at("elements_file").get<std::string>());
    const matrix_t boundary_source = read_matrix(params.at("boundary_file").get<std::string>());
    std::cout << "- Loaded brain data: " << X.rows() << " subjects, " << X.cols() << " mesh nodes" << std::endl;
    if (nodes.cols() != 3 || elements_source.cols() != 4 || boundary_source.cols() != 1) {
        throw std::runtime_error("invalid 3D mesh input dimensions");
    }
    if (X.rows() != Y.rows() || X.cols() != nodes.rows()) {
        throw std::runtime_error("X, Y, and mesh-node dimensions do not agree");
    }

    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> elements = elements_source.cast<int>();
    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> boundary = boundary_source.cast<int>();
    std::cout << "- Building tetrahedral FEM space: " << elements.rows() << " elements" << std::endl;
    Triangulation<3, 3> domain(nodes, elements, boundary, cache_cells);
    FeSpace space(domain, P1<1>);
    TrialFunction f(space);
    TestFunction v(space);
    const auto penalty = integral(domain)(dot(grad(f), grad(v)));
    ZeroField<3> forcing;
    const auto load = integral(domain)(forcing * v);
    GeoFrame data(domain);
    auto& layer = data.template insert_scalar_layer<POINT>("observations", MESH_NODES);
    layer.load_blk("X", X.transpose());

    auto direction_penalty = fe_ls_elliptic(penalty, load);
    auto loading_penalty = fe_ls_elliptic(penalty, load);
    fPLS model("X", Y, data, std::move(direction_penalty), std::move(loading_penalty));
    const auto setup_end = std::chrono::steady_clock::now();

    matrix_t direction_lambdas;
    matrix_t loading_lambdas;
    std::cout << "Starting fPLS fit: H=" << n_comp << ", calibration=" << calibration;
    if (calibration == "gcv") std::cout << ", " << lambda_grid.size() << " candidate lambdas";
    std::cout << std::endl;
    if (calibration == "gcv") {
        if (lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");
        model.fit(n_comp, lambda_grid, lambda_grid, OptimizeGCV, max_iter, tolerance, gcv_probes, gcv_seed);
        direction_lambdas = model.direction_lambda();
        loading_lambdas = model.loading_lambda();
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

    std::filesystem::create_directories(output_dir);
    write_csv(output_file(output_dir, "x_space_directions_coefficients.csv"), model.X_space_directions());
    write_csv(output_file(output_dir, "y_space_directions.csv"), model.Y_space_directions());
    write_csv(output_file(output_dir, "x_latent_scores.csv"), model.X_latent_scores());
    write_csv(output_file(output_dir, "y_latent_scores.csv"), model.Y_latent_scores());
    write_csv(output_file(output_dir, "x_loadings_coefficients.csv"), model.X_loadings());
    write_csv(output_file(output_dir, "y_loadings.csv"), model.Y_loadings());
    write_csv(output_file(output_dir, "direction_lambdas.csv"), direction_lambdas);
    write_csv(output_file(output_dir, "loading_lambdas.csv"), loading_lambdas);
    matrix_t component_diagnostics(n_comp, 6);
    for (int h = 0; h < n_comp; ++h) {
        const auto& history = model.direction_objective_history()[h];
        Eigen::Map<const matrix_t> history_matrix(history.data(), history.size(), 1);
        write_csv(output_file(output_dir, "objective_history_h" + std::to_string(h + 1) + ".csv"), history_matrix);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.direction_iterations()[h];
        component_diagnostics(h, 2) = model.direction_monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ? std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.direction_iterations()[h] >= max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) = !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;
        std::cout << "- Component " << h + 1 << '/' << n_comp
                  << " completed: direction lambda=" << direction_lambdas(h, 0)
                  << ", iterations=" << model.direction_iterations()[h] << std::endl;
    }
    write_csv(
      output_file(output_dir, "component_diagnostics.csv"), component_diagnostics,
      std::vector<std::string> {"component", "iterations", "monotone", "objective", "hit_max_iter", "finite_solution"});

    json component_files = json::array();
    for (int h = 1; h <= n_comp; ++h) {
        const std::string suffix = "_h" + std::to_string(h) + ".csv";
        write_csv(output_file(output_dir, "y_hat" + suffix), model.fitted(h));
        json files {{"component", h}, {"y_hat", "y_hat" + suffix}};
        if (write_reconstructions) {
            write_csv(output_file(output_dir, "x_hat_locations" + suffix), model.reconstructed(h));
            files["x_hat_locations"] = "x_hat_locations" + suffix;
        }
        if (write_beta) {
            write_csv(output_file(output_dir, "beta_coefficients" + suffix), model.Beta(h));
            files["beta_coefficients"] = "beta_coefficients" + suffix;
        }
        component_files.push_back(std::move(files));
    }
    const auto output_end = std::chrono::steady_clock::now();

    const double setup_seconds = std::chrono::duration<double>(setup_end - wall_start).count();
    const double fit_seconds = std::chrono::duration<double>(fit_end - setup_end).count();
    const double output_seconds = std::chrono::duration<double>(output_end - fit_end).count();
    const double wall_seconds = std::chrono::duration<double>(output_end - wall_start).count();
    std::vector<int> monotone;
    monotone.reserve(model.direction_monotone().size());
    for (bool value : model.direction_monotone()) monotone.push_back(value ? 1 : 0);

    json telemetry_json;
    telemetry_json["schema_version"] = 1;
    telemetry_json["model"] = "R1_fPLS";
    telemetry_json["mode"] = "native_fdaPDE_cpp";
    telemetry_json["discretization"] = "tetrahedral_fem";
    telemetry_json["center"] = false;
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
    telemetry_json["fixed_direction_lambda"] = fixed_direction_lambda;
    telemetry_json["fixed_loading_lambda"] = fixed_loading_lambda;
    telemetry_json["setup_seconds"] = setup_seconds;
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

int main(int argc, char* argv[]) {
    try {
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " <params.json>\n";
            return 1;
        }
        std::ifstream input(argv[1]);
        if (!input) throw std::runtime_error("cannot open parameter file");
        return run_application(json::parse(input));
    } catch (const std::exception& error) {
        std::cerr << "fPLS application failed: " << error.what() << '\n';
        return 2;
    }
}
