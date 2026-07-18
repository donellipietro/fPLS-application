# fPLS Neuroimaging Application

This repository ports the fPLS resting-state fMRI connectivity application to the current native fdaPDE C++ implementation. It is scoped to the reviewer-facing application analysis, not to the historical simulation suites.

The application compares control and schizophrenia groups using imputed brain connectivity maps on a volumetric tetrahedral mesh. The response is the historical CNTRL-vs-SCHZ binary contrast recoded with prevalence weights, and the functional predictor maps are centered by the authoritative overall functional mean. The historical script's accidental overwrite from `overall_mean` to `group_means` is not preserved as active behavior.

## Analysis Scope

- Fit native R1-fPLS on the 3D brain mesh with `tol = 1e-8`, `max_iter = 1000`, and deterministic GCV seed `0`.
- Inventory the historical application GCV grid, `10^seq(-3, -1, by = 0.2)`, in configuration.
- Retain `H = 3` as the exploratory application setting to be verified as the first component count with perfect in-sample group separation.
- Plan distinct fits for larger `H` values, initially `4:6`, and compare the first three loading functions by sign-aligned FEM mass relative norm.
- Record selected lambdas, component iterations, objective/monotonicity diagnostics, non-finite/failure status, wall-clock time, peak RAM, runtime profile, and exact fdaPDE commits.

Raw brain data and generated outputs are intentionally outside Git. The default local data path is the historical ignored application input folder:

```sh
/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain
```

Override it with `TESTBENCH_PATH_APPLICATION_DATA=/path/to/brain-data`.

## Minimal Local Workflow

Write the profile and create generated directories:

```sh
TESTBENCH_PATH_FDAPDE_CPP=/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp \
TESTBENCH_FDAPDE_CPP_MANAGED=false \
Rscript config.R --profile macbook --write-env

Rscript config.R --profile macbook --create-dirs
```

Compile the native 3D driver:

```sh
make compile MODEL=brain TARGET=fit_model
```

Run the non-expensive application smoke check, which prepares and records the authoritative centered data but skips the native fit:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=smoke_overall_mean
```

The planned H-stability run is intentionally not a smoke command. Confirm runtime before executing it:

```sh
make run_test TEST_SUITE=brain TEST_NAME=h_stability
```

See [docs/provenance.md](docs/provenance.md) for source, template, native-stack, and data-provenance details.
