# fPLS Neuroimaging Application

This repository contains the native fdaPDE implementation of the fPLS task-based functional-connectivity application. It compares control (`CTRL`) and schizophrenia (`SCHZ`) groups on a volumetric tetrahedral mesh.

The predictor is centered by a GCV-smoothed overall functional mean in the tetrahedral P1 finite-element space. The response preserves the prevalence-weighted binary coding:

- `CTRL`: `sqrt(p_SCHZ / p_CTRL)`
- `SCHZ`: `-sqrt(p_CTRL / p_SCHZ)`

## Analysis targets

The suite contains four targets:

- `smoke_overall_mean`: validates input loading, response coding, and functional-mean preparation without a native model fit.
- `h_stability`: fits one complete-data R1-fPLS model through `H = 6`, reports prefix separation, verifies the first perfectly separating prefix, and compares the intrinsic slider at `H = 4:6` with `H = 3` using tetrahedral FEM mass metrics. Native `Beta(H)` is compared over the same prefixes.
- `slider_resampling`: runs 10 repeats of stratified five-fold delete-one-fold sampling, for 50 training-only R1-fPLS fits. Each fit re-estimates centering, response coding, regularization, and the intrinsic `H = 3` slider. Omitted subjects define the perturbation and are not used for fitted quantities or metrics.
- `fpcr_h20_separation`: fits the complete-data fPCR comparator through `H = 20` and reports prefix separation with its fPCA GCV diagnostics.

For retained scores `T_H`, component standard deviations `D_H`, X loadings `R_H`, and response loadings `nu_H`, the intrinsic fPLS direction and functional slider are

```text
q_H = D_H nu_H / ||D_H nu_H||
f_H = R_H D_H q_H.
```

The exact threshold is selected from the oriented fitted response by maximizing sensitivity plus specificity. At `H = 3`, it is transformed into standardized intrinsic-slider coordinates and saved with the subject scores.

## Data

Raw data are external to Git. `PATH_APPLICATION_DATA` must contain:

- `FEMbasis.Rds`
- `X_imputed.rds`
- `Ycl.rds`

The default path is `data/brain` relative to the repository. Override it with `PATH_APPLICATION_DATA=/path/to/brain-data` when the inputs live elsewhere.

Generated data, results, images, logs, queues, build products, libraries, and provenance artifacts are ignored by Git.

## Local setup and execution

Create the environment, directories, R dependencies, JSON headers, and pinned fdaPDE checkout:

```sh
make build PROFILE=macbook
```

An existing fdaPDE checkout can be used without modification:

```sh
PATH_FDAPDE_CPP=/path/to/fdaPDE-cpp \
FDAPDE_CPP_MANAGED=false \
make build PROFILE=macbook
```

Compile and run targets with:

```sh
make compile MODEL=brain TARGET=fit_model
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=smoke_overall_mean
make run_test TEST_SUITE=brain TEST_NAME=h_stability
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h20_separation
```

The local profile uses independent parallel workers while each native fit remains single-threaded. `SMOKE_TEST=1` reduces slider resampling to two folds and three components.

## PBS execution

The `hpc-torque` profile compiles and runs through PBS. It distributes option files across workers and submits aggregation after successful fits.

```sh
PATH_APPLICATION_DATA=/cluster/path/to/brain-data make build PROFILE=hpc-torque
make run_test TEST_SUITE=brain TEST_NAME=h_stability
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h20_separation
```

Inspect job commands without sending them to PBS:

```sh
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 \
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
```

Resource requests can be adjusted with `PBS_MAX_JOBS`, `PBS_QUEUE`, `PBS_ACCOUNT`, `PBS_CPUS`, `PBS_MEM`, and `PBS_TIME`.

## Outputs and figures

Aggregates are written below `results/brain/aggregate/<target>/`; figures are written below `images/brain/aggregate/<target>/`.

The complete-data R1-fPLS aggregate includes:

- `separation_by_H.csv`
- `intrinsic_fpls_slider_stability_by_H.csv`
- `intrinsic_fpls_slider_coordinates_by_H.csv`
- `intrinsic_fpls_scores_H3.csv`
- `intrinsic_fpls_slider_maps/reconstruction_loading_h3.csv` through `h6.csv`
- `beta_stability_by_H.csv`
- regularization, resource, run-status, telemetry, and provenance records

The resampling aggregate includes fold diagnostics, the first-perfect-prefix distribution, all 50 intrinsic-slider comparisons with the complete-data `H = 3` map, descriptive summaries, regularization diagnostics, and resources.

Generate the two application figure panels from the recorded complete-data result files:

```sh
make application_figure_panels
```

See [tests/README.md](tests/README.md), [paper-figures/README.md](paper-figures/README.md), and [docs/provenance.md](docs/provenance.md) for suite, figure-source, and provenance details.
