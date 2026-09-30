#include <fdaPDE/models.h>

#include "output.h"

/** @brief prepare and center brain observations, fit rank-one fPLS and export component prefixes */
int run_fpls(const simulation_parameters& params) {
    // begin native workflow timing before loading the training data and mesh
    const auto wall_start = std::chrono::steady_clock::now();

    // load training predictors with subjects in rows and mesh nodes in columns, together with the responses
    const matrix_t X_raw = read_matrix(params.X_file);
    const matrix_t Y = read_matrix(params.Y_file);

    // read node coordinates, tetrahedral connectivity and boundary-node markers
    const matrix_t nodes = read_matrix(params.nodes_file);
    const matrix_t elements_source = read_matrix(params.elements_file);
    const matrix_t boundary_source = read_matrix(params.boundary_file);

    // report the training-data size before constructing the finite-element domain
    std::cout << "- Loaded brain data: " << X_raw.rows() << " subjects, " << X_raw.cols() << " mesh nodes" << std::endl;

    // check mesh input shapes and agreement between subjects, responses and observation nodes
    if (nodes.cols() != 3 || elements_source.cols() != 4 || boundary_source.cols() != 1) {
        throw std::runtime_error("invalid 3D mesh input dimensions");
    }
    if (X_raw.rows() != Y.rows() || X_raw.cols() != nodes.rows()) {
        throw std::runtime_error("X, Y, and mesh-node dimensions do not agree");
    }

    // convert connectivity and boundary markers to the integer format required by the mesh constructor
    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> elements = elements_source.cast<int>();
    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> boundary = boundary_source.cast<int>();

    // report mesh size before assembling the volumetric domain and function space
    std::cout << "- Building tetrahedral FEM space: " << elements.rows() << " elements" << std::endl;

    // define the volumetric domain and continuous piecewise-linear finite-element space
    Triangulation<3, 3> domain(nodes, elements, boundary, cache_cells);
    FeSpace space(domain, P1<1>);

    // define trial and test functions for the variational smoothing forms
    TrialFunction f(space);
    TestFunction v(space);

    // define the weak Laplacian bilinear form for the elliptic smoothing penalties
    const auto penalty = integral(domain)(dot(grad(f), grad(v)));

    // define the homogeneous PDE load with zero forcing
    ZeroField<3> forcing;
    const auto load = integral(domain)(forcing * v);

    // measurements coincide with mesh nodes, so no separate observation grid is needed
    GeoFrame data(domain);
    auto& layer = data.template insert_scalar_layer<POINT>("observations", MESH_NODES);

    // begin functional-centering timing before preparing the mean smoother
    const auto centering_start = std::chrono::steady_clock::now();

    // build the elliptic smoother for the training-only mean with equal nodal weights
    auto mean_penalty = fe_ls_elliptic(penalty, load);
    fdapde::internals::fe_ls_elliptic mean_smoother;
    mean_smoother.discretize(mean_penalty.get());
    mean_smoother.analyze_data(data, vector_t::Ones(data[0].rows()).asDiagonal());

    // report the candidate-grid size before calibrating the functional mean
    std::cout << "- Fitting training-only functional mean by GCV over " << params.mean_lambda_grid.size()
              << " candidate lambda(s)" << std::endl;

    // smooth the empirical training mean and select its lambda by GCV
    const functional_mean_fit mean_fit = fit_functional_mean_gcv(
      X_raw,                     // training predictors before functional centering
      mean_smoother,             // elliptic smoother for the mean function
      params.mean_lambda_grid,   // candidate lambdas for smoothing the empirical mean
      params.mean_gcv_probes,    // number of Hutchinson probes for mean effective degrees of freedom
      params.mean_gcv_seed       // seed for stochastic mean effective degrees of freedom
    );

    // subtract the same training-only smooth mean from each subject's predictor curve
    const matrix_t X = X_raw.rowwise() - mean_fit.locations.transpose();

    // require finite centered predictors before binding them to the model data layer
    if (!X.allFinite()) throw std::runtime_error("functional-mean centered data are non-finite");

    // store locations in rows and subjects in columns as required by GeoFrame
    layer.load_blk("X", X.transpose());

    // finish functional-centering timing once the centered observations have been loaded
    const auto centering_end = std::chrono::steady_clock::now();

    // report the selected mean smoothing parameter before exporting preprocessing diagnostics
    std::cout << "- Functional mean completed: lambda=" << mean_fit.selected_lambda << std::endl;

    // export the estimated functional mean and its GCV diagnostics
    write_functional_mean_output(
      params.output_dir,        // destination for the preprocessing outputs
      mean_fit,                 // selected mean in coefficient and nodal form, with its EDF/GCV diagnostics
      params.mean_lambda_grid   // candidate lambdas paired with the exported EDF and GCV values
    );

    // model definition: separate elliptic smoothers for directions and reconstruction loadings
    auto direction_penalty = fe_ls_elliptic(penalty, load);
    auto loading_penalty = fe_ls_elliptic(penalty, load);
    fPLS model("X", Y, data, std::move(direction_penalty), std::move(loading_penalty));

    // finish setup timing before the calibration and fitting stage
    const auto setup_end = std::chrono::steady_clock::now();

    // print model size and calibration settings before starting the fit
    std::cout << "Starting fPLS fit: H=" << params.n_comp << ", calibration=" << params.calibration;
    if (params.calibration == "gcv") std::cout << ", " << params.lambda_grid.size() << " candidate lambdas";
    std::cout << std::endl;

    // calibrate per component by GCV or use one fixed lambda for each penalty
    if (params.calibration == "gcv") {
        if (params.lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");

        // estimate supervised directions and loadings with component-wise GCV
        model.fit(
          params.n_comp,        // number of retained components
          params.lambda_grid,   // candidate lambdas for direction smoothing
          params.lambda_grid,   // candidate lambdas for loading smoothing
          OptimizeGCV,          // select both smoothing parameters by GCV per component
          params.max_iter,      // maximum alternating direction updates per component
          params.tolerance,     // objective tolerance for stopping and increase diagnostics
          params.gcv_probes,    // number of Hutchinson probes for effective degrees of freedom
          params.gcv_seed       // seed for stochastic effective degrees of freedom
        );
    } else if (params.calibration == "fixed") {
        // wrap fixed direction/loading lambdas in the matrix form required by the fit overload
        Eigen::Matrix<double, 1, 1> direction_lambda;
        Eigen::Matrix<double, 1, 1> loading_lambda;
        direction_lambda << params.fixed_direction_lambda;
        loading_lambda << params.fixed_loading_lambda;

        // estimate all components using the supplied fixed smoothing parameters
        model.fit(
          params.n_comp,      // number of retained components
          direction_lambda,   // fixed direction lambda shared by all components
          loading_lambda,     // fixed loading lambda shared by all components
          params.max_iter,    // maximum alternating direction updates per component
          params.tolerance    // objective tolerance for stopping and increase diagnostics
        );
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }

    // finish model-stage timing after calibration and fitting
    const auto fit_end = std::chrono::steady_clock::now();

    // export model coefficients, fitted responses and convergence diagnostics
    return write_fpls_output(
      params, space, model, X, Y, mean_fit,   // output context, fitted model, training data and mean fit
      wall_start, setup_end, fit_end, centering_start, centering_end   // model-stage and centering timing checkpoints
    );
}

/** @brief prepare and center brain observations, fit fPCR and export its prefix regressions */
int run_fpcr(const simulation_parameters& params) {
    // begin native workflow timing before loading the training data and mesh
    const auto wall_start = std::chrono::steady_clock::now();

    // load training predictors with subjects in rows and mesh nodes in columns, together with the responses
    const matrix_t X_raw = read_matrix(params.X_file);
    const matrix_t Y = read_matrix(params.Y_file);

    // read node coordinates, tetrahedral connectivity and boundary-node markers
    const matrix_t nodes = read_matrix(params.nodes_file);
    const matrix_t elements_source = read_matrix(params.elements_file);
    const matrix_t boundary_source = read_matrix(params.boundary_file);

    // report the training-data size before constructing the finite-element domain
    std::cout << "- Loaded brain data: " << X_raw.rows() << " subjects, " << X_raw.cols() << " mesh nodes" << std::endl;

    // check mesh input shapes and agreement between subjects, responses and observation nodes
    if (nodes.cols() != 3 || elements_source.cols() != 4 || boundary_source.cols() != 1) {
        throw std::runtime_error("invalid 3D mesh input dimensions");
    }
    if (X_raw.rows() != Y.rows() || X_raw.cols() != nodes.rows()) {
        throw std::runtime_error("X, Y, and mesh-node dimensions do not agree");
    }

    // convert connectivity and boundary markers to the integer format required by the mesh constructor
    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> elements = elements_source.cast<int>();
    Eigen::Matrix<int, Eigen::Dynamic, Eigen::Dynamic> boundary = boundary_source.cast<int>();

    // report mesh size before assembling the volumetric domain and function space
    std::cout << "- Building tetrahedral FEM space: " << elements.rows() << " elements" << std::endl;

    // define the volumetric domain and continuous piecewise-linear finite-element space
    Triangulation<3, 3> domain(nodes, elements, boundary, cache_cells);
    FeSpace space(domain, P1<1>);

    // define trial and test functions for the variational smoothing forms
    TrialFunction f(space);
    TestFunction v(space);

    // define the weak Laplacian bilinear form for the elliptic smoothing penalties
    const auto penalty = integral(domain)(dot(grad(f), grad(v)));

    // define the homogeneous PDE load with zero forcing
    ZeroField<3> forcing;
    const auto load = integral(domain)(forcing * v);

    // measurements coincide with mesh nodes, so no separate observation grid is needed
    GeoFrame data(domain);
    auto& layer = data.template insert_scalar_layer<POINT>("observations", MESH_NODES);

    // begin functional-centering timing before preparing the mean smoother
    const auto centering_start = std::chrono::steady_clock::now();

    // build the elliptic smoother for the training-only mean with equal nodal weights
    auto mean_penalty = fe_ls_elliptic(penalty, load);
    fdapde::internals::fe_ls_elliptic mean_smoother;
    mean_smoother.discretize(mean_penalty.get());
    mean_smoother.analyze_data(data, vector_t::Ones(data[0].rows()).asDiagonal());

    // report the candidate-grid size before calibrating the functional mean
    std::cout << "- Fitting training-only functional mean by GCV over " << params.mean_lambda_grid.size()
              << " candidate lambda(s)" << std::endl;

    // smooth the empirical training mean and select its lambda by GCV
    const functional_mean_fit mean_fit = fit_functional_mean_gcv(
      X_raw,                     // training predictors before functional centering
      mean_smoother,             // elliptic smoother for the mean function
      params.mean_lambda_grid,   // candidate lambdas for smoothing the empirical mean
      params.mean_gcv_probes,    // number of Hutchinson probes for mean effective degrees of freedom
      params.mean_gcv_seed       // seed for stochastic mean effective degrees of freedom
    );

    // subtract the same training-only smooth mean from each subject's predictor curve
    const matrix_t X = X_raw.rowwise() - mean_fit.locations.transpose();

    // require finite centered predictors before binding them to the model data layer
    if (!X.allFinite()) throw std::runtime_error("functional-mean centered data are non-finite");

    // store locations in rows and subjects in columns as required by GeoFrame
    layer.load_blk("X", X.transpose());

    // finish functional-centering timing once the centered observations have been loaded
    const auto centering_end = std::chrono::steady_clock::now();

    // report the selected mean smoothing parameter before exporting preprocessing diagnostics
    std::cout << "- Functional mean completed: lambda=" << mean_fit.selected_lambda << std::endl;

    // export the estimated functional mean and its GCV diagnostics
    write_functional_mean_output(
      params.output_dir,        // destination for the preprocessing outputs
      mean_fit,                 // selected mean in coefficient and nodal form, with its EDF/GCV diagnostics
      params.mean_lambda_grid   // candidate lambdas paired with the exported EDF and GCV values
    );

    // model definition: smooth principal components followed by OLS for every sequential score prefix
    fPCR model("X", Y, data, fe_ls_elliptic(penalty, load));

    // finish setup timing before the calibration and fitting stage
    const auto setup_end = std::chrono::steady_clock::now();

    // print model size and calibration settings before starting the fit
    std::cout << "Starting fPCR fit: H=" << params.n_comp << ", calibration=" << params.calibration;
    if (params.calibration == "gcv") std::cout << ", " << params.lambda_grid.size() << " candidate lambdas";
    std::cout << std::endl;

    // keep stochastic calibration reproducible and select the public fixed or GCV fit path
    if (params.calibration == "gcv") {
        if (params.gcv_seed == random_seed)
            throw std::runtime_error("fPCR GCV requires an explicit deterministic seed");

        // estimate smooth components with exact SVD initialization and explicit EDF controls for GCV
        model.fit(
          params.n_comp,                  // number of retained components
          params.lambda_grid,             // candidate lambdas for principal-component smoothing
          OptimizeGCV | ComputeXactSVD,   // component-wise GCV with exact SVD initialization
          params.max_iter,                // maximum score/loading updates per component
          params.tolerance,               // objective tolerance for stopping and increase diagnostics
          params.gcv_probes,              // number of Hutchinson probes for effective degrees of freedom
          params.gcv_seed                 // deterministic seed for stochastic effective degrees of freedom
        );
    } else if (params.calibration == "fixed") {
        // estimate all components with exact SVD initialization and the supplied fixed lambda
        model.fit(
          params.n_comp,                                    // number of retained components
          std::vector<double> {params.fixed_fpca_lambda},   // fixed lambda shared by all components
          ComputeXactSVD,                                   // exact SVD initialization without GCV
          params.max_iter,                                  // maximum score/loading updates per component
          params.tolerance                                  // objective tolerance for stopping
        );
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }

    // finish solver timing after the component fit and all prefix-specific response regressions
    const auto fit_end = std::chrono::steady_clock::now();

    // export saved calibration diagnostics, prefix predictions and regression functions
    return write_fpcr_output(
      params, space, model, X, Y, mean_fit,   // output context, fitted model, training data and mean fit
      wall_start, setup_end, fit_end, centering_start, centering_end   // model-stage and centering timing checkpoints
    );
}

/** @brief read the application settings and run fPLS or its fPCR alternative */
int main(int argc, char* argv[]) {
    try {
        // read and validate the command-line parameter file
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " <params.json>\n";
            return 1;
        }
        const auto params = read_parameters(read_parameter_file(argv[1]));

        // dispatch fPLS as the base model, with fPCR as the alternative
        if (params.model_name == "R1_fPLS") {
            return run_fpls(params);
        } else {
            return run_fpcr(params);
        }
    } catch (const std::exception& error) {
        // report input, preprocessing or fitting failures through the existing nonzero exit status
        std::cerr << "brain application failed: " << error.what() << '\n';
        return 2;
    }
}
