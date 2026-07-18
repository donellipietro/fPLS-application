# Test Bench Capabilities

This document maps the reusable pieces available in the fdaPDE test bench.
For setup details and machine profiles, start from the root
[`README.md`](../README.md). For suite contracts, see
[`tests/README.md`](../tests/README.md).

## Runtime And Build

- **Runtime profiles:** `macbook`, `windows`, and `hpc-slurm` profiles in
  `config.R` configure paths, dependency management, compilation strategy, test
  execution strategy, containers, and Slurm defaults.
- **Dependency preparation:** `make build PROFILE=<profile>` creates the
  generated directory tree, writes `.env`, installs required R packages, prepares
  nlohmann/json, optionally pulls Docker/Apptainer images, and prepares a
  managed or user-provided `fdaPDE-cpp` checkout.
- **C++ compilation:** `make compile MODEL=<suite>` builds all suite drivers,
  `make compile MODEL=<suite> TARGET=<executable>` builds one executable, and
  `make compile_all` builds every driver under `cpp/`. Compilation can run
  locally or through Slurm according to the active profile.
- **Execution strategies:** `make run_test` can run option files serially,
  through GNU Parallel, or through Slurm arrays. `SMOKE_TEST=1` lets suites
  shrink grids/repetitions for quick checks.

## Suite Lifecycle

- **Option queues:** `src/init.R` calls each suite's
  `utils/generate_options.R`, expands option grids with `explode_options()`,
  writes one JSON option file per cell, and resolves grouped test names.
- **Model wrappers:** Suite `utils/wrappers.R` files export generated data and
  meshes, write C++ parameter JSON, run fitted-model executables, collect logs,
  and return standard model objects.
- **Evaluation outputs:** Suite `utils/models_evaluation.R` files compute
  per-model metrics and telemetry. Batch results are saved as standard
  `batch_<i>_fitted_model_<model>.RData` and
  `batch_<i>_results_evaluation.RData` files.
- **Result loading and aggregation:** `src/utils/load_results_utils.R` loads
  batch outputs, merges quantitative metrics, preserves model metadata, and can
  attach varying-option columns for plotting/reporting.

## Batch Cache

- **Complete batch skipping:** suites can skip a batch when generated data,
  fitted models, and evaluation files are already present and match the current
  options.
- **Generated data reuse:** matching generated data can be reused when
  fits/evaluations need refreshing.
- **Cache signatures:** cached generated data stores option and seed signatures
  so stale outputs are regenerated instead of silently reused.

## Shared Utilities

- **Metrics and telemetry:** `src/utils/error_metrics.R` provides RMSE-style
  helpers. `system_with_memory()` records wall time and peak RSS in MiB using
  `/usr/bin/time`, including Docker/container runs.
- **Domain and mesh utilities:** `src/utils/domain_utils.R` and
  `src/utils/mesh_utils.R` import bundled meshes, generate domains/locations,
  and build grid meshes for spatial experiments.
- **Data generators:** `src/data-generation/` contains 1D and 2D function
  generators for synthetic functional/spatial test data.
- **Directory and option helpers:** `src/utils/directories.R`,
  `src/utils/options.R`, `src/utils/config.R`, and
  `src/utils/test_groups.R` keep path, JSON option, profile, and grouped-test
  handling consistent.

## Plotting

- **Themes:** `std_plot_settings()`, `std_plot_settings_fields()`, and
  `std_plot_settings_curves()` provide standard ggplot styling.
- **Spatial and curve plots:** `plot.points()`, `plot.field_points()`,
  `plot.field_tile()`, `plot.curve()`, and `plot.curve_points()` cover common
  diagnostic views.
- **Aggregate plots:** grouped boxplots, violins, multiple lines, and
  `plot.aggregated_data()` support quantitative result pages.
- **ParaView palettes:** tile field plots accept `palette = "<ParaView name>"`
  or a custom colour vector/list. `paraview_colormap_names()` lists the 199
  bundled ParaView presets from `src/utils/paraview_colormaps.json`, and
  `paraview_colormap()` returns ggplot-ready colours.

## Suites And Outputs

- **Suite template:** `tests/template_base` documents the expected suite shape
  and is the starting point for new experiments.
- **Bundled example:** `tests/smoothing-example` compares 1D SRPDE FEM and
  spline solvers across `n_locs`, `n_nodes`, and SNR, including normalized RMSE,
  memory, timing, and qualitative aggregate plots.
- **Generated output roots:** the active profile controls result, image, test
  data, tmp, queue, log, build, dependency, and C++ paths.
- **Cleanup and inspection:** `make clean`, `make clean_test`, `make
  distclean`, and optional suite `inspect_results.R` scripts manage generated
  queues, logs, results, images, data, compiled binaries, and dependencies.
