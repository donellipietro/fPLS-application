# fPLS Neuroimaging Application

This repository contains the application code supporting the article and Supplementary Material for “Rank-One Functional Partial Least Squares Regression”.

The neuroimaging application uses the native fdaPDE implementation of R1-fPLS to compare control (`CTRL`) and schizophrenia (`SCHZ`) groups on a volumetric tetrahedral mesh.

The workflows correspond to the neuroimaging application section of the R1-fPLS article; the standardized score coordinate and functional-slider construction are derived in the supplementary section “Intrinsic R1-fPLS slider.”

The predictor is centered by a GCV-smoothed overall functional mean in the tetrahedral P1 finite-element space. The response preserves the prevalence-weighted binary coding:

- `CTRL`: `sqrt(p_SCHZ / p_CTRL)`
- `SCHZ`: `-sqrt(p_CTRL / p_SCHZ)`

## Analysis targets

The article and Supplementary Material use three analysis targets:

- `h_stability`: fits one complete-data R1-fPLS model through `H = 6`, reports separation at each component prefix and the first perfectly separating prefix, and compares the intrinsic slider at `H = 1:6` with `H = 3` using the tetrahedral FEM mass inner product.
- `slider_resampling`: runs 10 repeats of stratified five-fold delete-one-fold sampling, for 50 training-only R1-fPLS fits. Each fit re-estimates centering, response coding, regularization, and the intrinsic `H = 3` slider. Omitted subjects define the perturbation and are not used for fitted quantities or metrics.
- `fpcr_h20_separation`: fits the complete-data fPCR comparator through `H = 20` and reports prefix separation with its fPCA GCV diagnostics.

For retained scores `T_H`, component standard deviations `D_H`, X loadings `R_H`, and response loadings `nu_H`, the intrinsic fPLS direction and functional slider are

```text
q_H = D_H nu_H / ||D_H nu_H||
f_H = R_H D_H q_H.
```

The exact threshold is selected from the oriented fitted response by maximizing sensitivity plus specificity. At `H = 3`, it is transformed into standardized intrinsic-slider coordinates and saved with the subject scores.

## Data

The preprocessed inputs are private and are not distributed with this repository. `PATH_APPLICATION_DATA` must contain:

| File | MD5 |
| --- | --- |
| `FEMbasis.Rds` | `59433e991190b029f6f190b00c4f878a` |
| `X_imputed.rds` | `bf40b1320a4b0b115117d922ac2d08c3` |
| `Ycl.rds` | `e99aba962f10e0384d1897365a028bca` |

The default path is `data/brain` relative to the repository. If the inputs live elsewhere,
prefix the build command below with `PATH_APPLICATION_DATA=/path/to/brain-data`.

Generated data, results, images, logs, queues, build products, libraries, and provenance artifacts are ignored by Git.

## Prerequisites

Install the following on your machine before running the workflow:

- GNU Make, Bash, Git and R;
- a C++20 compiler and Eigen for the `macos`, `linux` and `hpc-torque` profiles;
- GNU Parallel and `bc` for parallel execution.

The `windows` profile uses Docker Desktop with WSL2 integration. The `hpc-slurm` profile
requires Slurm and Apptainer or SingularityCE. `hpc-torque` submits jobs through Torque/PBS.

`make build` automatically installs the missing R packages listed in the
[installation script](src/installation/install_femR.R), and prepares the nlohmann/json
headers and the pinned `fdaPDE-cpp` stack. The native revisions are pinned in
[`config.R`](config.R): fdaPDE-cpp commit `d32e453` and core commit `472f9bd`.

Additional software needed to generate manuscript panels is listed in the
[figure guide](paper-figures/README.md#prerequisites).

## Setup and execution

Choose `macos` on macOS, `linux` on Linux, `windows` under WSL2, or the matching
`hpc-slurm` or `hpc-torque` cluster profile. Run the build from the repository root;
it saves the selected profile in `.env`, and subsequent commands reuse it:

```sh
make build PROFILE=macos
```

The `macos` profile uses Homebrew GCC 15 and Eigen paths; `linux` uses system GCC and
`/usr/include/eigen3`. Override `CC`, `CXX`, or `PATH_EIGEN_INCLUDE` if needed.
The build prepares the configured container for `windows` and `hpc-slurm`.

`TEST_SUITE=brain` selects the application suite, and `TEST_NAME` selects an analysis
target. `make run_test` automatically compiles the required native executables:

```sh
# Fit the complete-data R1-fPLS model through H = 6
make run_test TEST_SUITE=brain TEST_NAME=h_stability
```

See the [analysis guide](tests/README.md) for the resampling and fPCR commands. Run
`h_stability` before `slider_resampling`, which uses its complete-data slider as the reference.
The local profile uses independent parallel workers while each native fit remains single-threaded.

## Results

After `make run_test`, aggregated results are available in `results/brain/aggregate/<TEST_NAME>/`
and figures in `images/brain/aggregate/<TEST_NAME>/`, relative to the repository root. For example,
`TEST_NAME=h_stability` writes results to `results/brain/aggregate/h_stability/` and figures to
`images/brain/aggregate/h_stability/`.

Once the complete `h_stability` results and associated raw files are available, generate the
manuscript panels from the repository root:

```sh
make application_figure_panels
```

See the [figure guide](paper-figures/README.md) for output locations and further options.
The [analysis guide](tests/README.md) also explains how to generate the supplementary
slider-similarity table from the 50 saved resampling fits. These are training-fit stability
summaries; the overlapping fits are not independent replicates.

## Native regression outputs

The native driver uses public fdaPDE-cpp fPLS and fPCR models. GCV diagnostics contain the candidate evaluations and EDF saved during calibration, with no diagnostic refit. Application output schema 4 renames `replay_minimum` to `grid_minimum` and exports fPCR predictions, beta coefficients and errors for every response column. Scalar classification metrics retain their original interpretation. See [the native output schema](cpp/brain/OUTPUT_SCHEMA.md) for column order, telemetry and timing details.

## Reproducibility limits

This repository starts from the finite-element basis, an already imputed predictor matrix, and group labels. It does not reconstruct upstream fMRI preprocessing, missing-value imputation, or selection of the seed region. The workflows are descriptive fitted-sample analyses and do not provide out-of-sample validation. Numerical reproduction requires the private preprocessed inputs and the pinned native fdaPDE stack.

See the [analysis guide](tests/README.md) and [figure sources](paper-figures/README.md) for the application workflow and manuscript outputs.
