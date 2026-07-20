# fPLS Neuroimaging Application

This repository ports the fPLS resting-state fMRI connectivity application to the current native fdaPDE C++ implementation. It is scoped to the reviewer-facing application analysis, not to the historical simulation suites.

The application compares control and schizophrenia groups using imputed brain connectivity maps on a volumetric tetrahedral mesh. The response is the historical CNTRL-vs-SCHZ binary contrast recoded with prevalence weights, and the functional predictor maps are centered by the authoritative overall functional mean. The historical script's accidental overwrite from `overall_mean` to `group_means` is not preserved as active behavior.

## Analysis Scope

- Fit native R1-fPLS on the 3D brain mesh with `tol = 1e-8`, `max_iter = 1000`, and deterministic GCV seed `0`.
- Inventory the historical application GCV grid, `10^seq(-3, -1, by = 0.2)`, in configuration.
- Fit a single sequential `H = 6` model and report prefix-wise separation diagnostics for `H = 3:6`; `H = 3` remains the exploratory setting to be verified as the first prefix with perfect in-sample separation.
- This initial run does not estimate loading stability across distinct fits, because the requested prefixes come from one sequential fit.
- Record selected lambdas, component iterations, objective/monotonicity diagnostics, non-finite/failure status, wall-clock time, peak RAM, runtime profile, and exact fdaPDE commits.

Raw brain data and generated outputs are intentionally outside Git. The default local data path is the historical ignored application input folder:

```sh
/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain
```

Override it with `TESTBENCH_PATH_APPLICATION_DATA=/path/to/brain-data`.

The native fdaPDE stack is cloned locally into the ignored `libraries/fdaPDE-cpp` directory on `develop_fPLS`; the application does not run against the simulation repository checkout.

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

The planned `H = 6` prefix-diagnostics run is intentionally not a smoke command. A native failure is recorded in the aggregate status and returned as a nonzero command status:

```sh
make run_test TEST_SUITE=brain TEST_NAME=h_stability
```

In a second terminal, inspect or follow the native progress log:

```sh
make h_stability_logs
make h_stability_tail
```

Completed H-prefix separation diagnostics are written to
`results/brain/aggregate/h_stability/separation_by_H.csv`, with the compact
figure at `images/brain/aggregate/h_stability/separation_by_H.png`.

See [docs/provenance.md](docs/provenance.md) for source, template, native-stack, and data-provenance details.
