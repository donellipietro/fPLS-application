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

The default path is `data/brain` relative to the repository. Override it with `PATH_APPLICATION_DATA=/path/to/brain-data` when the inputs live elsewhere.

Generated data, results, images, logs, queues, build products, libraries, and provenance artifacts are ignored by Git.

## Prerequisites

The analysis runtime requires R, GNU Make, Bash, Git, a C++20 compiler, and Eigen. Local parallel execution additionally requires GNU Parallel; the `hpc-torque` profile requires a PBS client providing `qsub`. Dependencies used only to generate manuscript panels are listed separately in [paper-figures/README.md](paper-figures/README.md).

## Local setup and execution

Create the environment, directories, R dependencies, JSON headers, and pinned fdaPDE checkout:

```sh
make build PROFILE=macbook
```

An existing fdaPDE checkout matching the revisions pinned in `config.R` can be used:

```sh
PATH_FDAPDE_CPP=/path/to/fdaPDE-cpp \
FDAPDE_CPP_MANAGED=false \
make build PROFILE=macbook
```

Compile and run targets with:

```sh
make compile MODEL=brain TARGET=fit_model
make run_test TEST_SUITE=brain TEST_NAME=h_stability
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h20_separation
```

The local profile uses independent parallel workers while each native fit remains single-threaded.

## PBS execution

The `hpc-torque` profile compiles and runs through PBS. It distributes option files across workers and submits aggregation after successful fits.

```sh
PATH_APPLICATION_DATA=/cluster/path/to/brain-data make build PROFILE=hpc-torque
make run_test TEST_SUITE=brain TEST_NAME=h_stability
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h20_separation
```

Resource requests can be adjusted with `PBS_MAX_JOBS`, `PBS_QUEUE`, `PBS_ACCOUNT`, `PBS_CPUS`, `PBS_MEM`, and `PBS_TIME`.

## Outputs and figures

Aggregates are written below `results/brain/aggregate/<target>/`; figures are written below `images/brain/aggregate/<target>/`.

The complete-data R1-fPLS outputs used by the article and Supplementary Material include:

- `separation_by_H.csv`
- `intrinsic_fpls_slider_stability_by_H.csv`
- `intrinsic_fpls_slider_coordinates_by_H.csv`
- `intrinsic_fpls_scores_H3.csv`
- `intrinsic_fpls_slider_maps/reconstruction_loading_h1.csv` through `reconstruction_loading_h6.csv`
- regularization, resource, run-status, telemetry, and provenance records

The resampling aggregate includes fold diagnostics, the first-perfect-prefix distribution, all 50 intrinsic-slider comparisons with the complete-data `H = 3` map, descriptive summaries, regularization diagnostics, and resources.

To reproduce the supplementary slider-similarity table from the 50 saved six-component resampling fits:

```sh
Rscript tests/brain/postprocess_slider_resampling_by_H.R /path/to/results results/brain/aggregate/slider_resampling_by_H
```

This writes per-fold FEM comparisons and `summary_by_H.csv` against both the same fold's `H = 3` slider and the complete-data `H = 3` slider. The medians and quartiles of `rho_H` provide the supplementary table values. These are training-fit stability metrics, not held-out predictive performance; the 50 overlapping fits are not independent replicates.

Generate the two application figure panels from the recorded complete-data result files:

```sh
make application_figure_panels
```

## Reproducibility limits

This repository starts from the finite-element basis, an already imputed predictor matrix, and group labels. It does not reconstruct upstream fMRI preprocessing, missing-value imputation, or selection of the seed region. The workflows are descriptive fitted-sample analyses and do not provide out-of-sample validation. Numerical reproduction requires the private preprocessed inputs and the pinned native fdaPDE stack.

See [tests/README.md](tests/README.md), [paper-figures/README.md](paper-figures/README.md), and [docs/provenance.md](docs/provenance.md) for suite, figure-source, and provenance details.
