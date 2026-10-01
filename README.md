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

The data source and preprocessing used to obtain these inputs are described in the article's
“Application to functional connectivity data” section and the references cited there.
The preprocessed inputs are private and are not distributed with this repository.

The default path is `data/brain` relative to the repository. If the inputs live elsewhere,
prefix the build command below with `PATH_APPLICATION_DATA=/path/to/brain-data`.

Generated data, results, images, logs, queues, build products, libraries, and provenance artifacts are ignored by Git.

## Prerequisites

Install the following on your machine before running the workflow:

- GNU Make, Bash, Git and R;
- a C++20 compiler and Eigen for native compilation with the `macos` or `linux` profile;
- GNU Parallel and `bc` for parallel execution;
- Docker Desktop with WSL2 integration for the `windows` profile.

`make build` automatically installs the missing R packages listed in the
[installation script](src/installation/install_femR.R), and prepares the nlohmann/json
headers and the pinned `fdaPDE-cpp` stack. For the `windows` profile,
the build also prepares the configured Docker image.

Additional software needed to generate manuscript panels is listed in the
[figure guide](paper-figures/README.md#prerequisites).

For local execution, choose `macos` on macOS, `linux` on Linux, or `windows` on Windows.
The Linux profile uses `gcc`, `g++`, and Eigen in `/usr/include/eigen3`; override `CC`, `CXX`,
or `PATH_EIGEN_INCLUDE` if your installation uses different paths. Inspect a profile with:

```sh
make config PROFILE=macos
```

## Setup and execution

Select a profile when preparing the runtime. The build saves it in `.env`, and subsequent
commands reuse it. Run from the repository root:

```sh
make build PROFILE=macos
```

Use `PROFILE=linux` or `PROFILE=windows` for the corresponding platform.
`TEST_SUITE=brain` selects the application suite, and `TEST_NAME` selects an analysis
target or `all` to run and aggregate every analysis in the suite separately.
`make run_test` automatically compiles the selected suite before execution:

```sh
# Fit the complete-data R1-fPLS model through H = 6
make run_test TEST_SUITE=brain TEST_NAME=h_stability

# Run all analyses in the brain suite
make run_test TEST_SUITE=brain TEST_NAME=all
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

Once `h_stability` and all 50 `slider_resampling` fits are complete, generate the supplementary
slider-similarity table from the saved results:

```sh
make application_paper_tables
```

See the [figure guide](paper-figures/README.md) and [table guide](paper-tables/README.md)
for output locations and further options. The table reports training-fit stability summaries;
the overlapping fits are not independent replicates.

## Reproducibility limits

This repository starts from the finite-element basis, an already imputed predictor matrix, and group labels. It does not reconstruct upstream fMRI preprocessing, missing-value imputation, or selection of the seed region. The workflows are descriptive fitted-sample analyses and do not provide out-of-sample validation. Numerical reproduction requires the private preprocessed inputs and the pinned native fdaPDE stack.

See the [analysis guide](tests/README.md) and [figure sources](paper-figures/README.md) for the application workflow and manuscript outputs.

## Platform configuration and support

The native profiles were tested with the following reference environments:

| Profile | Platform | C++ compiler | R | Eigen |
| --- | --- | --- | --- | --- |
| `macos` | macOS 26.6.2, ARM64 | GCC/G++ 15.2.0 (Homebrew) | 4.3.3 | 3.4.0 |
| `linux` | Ubuntu 24.04.5 LTS, ARM64, in Docker | GCC/G++ 13.3.0 | 4.3.3 | 3.4.0 |

Profiles are also provided for Windows/WSL2 with Docker (`windows`), but this
profile could not be tested.

The Linux native driver was compiled in the environment above. Running the full
application requires the private inputs described in the Data section.

On Ubuntu/Debian, R packages compiled from source also need development libraries.
Install these before `make build PROFILE=linux`:

```sh
sudo apt-get update
sudo apt-get install -y build-essential r-base-dev libeigen3-dev \
  libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev cmake
```

This repository is maintained by Pietro Donelli. For questions or problems, contact
[pietro.donelli@polimi.it](mailto:pietro.donelli@polimi.it).
