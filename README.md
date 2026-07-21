# fPLS Neuroimaging Application

This repository ports the fPLS resting-state fMRI connectivity application to the current native fdaPDE C++ implementation. It is scoped to the reviewer-facing application analysis, not to the historical simulation suites.

The application compares control and schizophrenia groups using imputed brain connectivity maps on a volumetric tetrahedral mesh. The response is the historical CNTRL-vs-SCHZ binary contrast recoded with prevalence weights, and the functional predictor maps are centered by the authoritative overall functional mean. The historical script's accidental overwrite from `overall_mean` to `group_means` is not preserved as active behavior.

## Analysis Scope

- Fit native R1-fPLS on the 3D brain mesh with `tol = 1e-8`, `max_iter = 1000`, and deterministic GCV seed `0`.
- Inventory the historical application GCV grid, `10^seq(-3, -1, by = 0.2)`, in configuration.
- Fit a single sequential `H = 6` model and report prefix-wise separation diagnostics for `H = 3:6`; `H = 3` remains the exploratory setting to be verified as the first prefix with perfect in-sample separation.
- Use fPLS for dimension reduction, then estimate the maximum-margin linear boundary in each standardized score prefix `H = 3:6`. This is an in-sample exploratory boundary, not a cross-validated diagnostic classifier.
- Map each score-space boundary to both its reconstructed connectivity pattern and its exact functional classifier coefficient, then compare both maps with their `H = 3` references using tetrahedral FEM mass correlations.
- Estimate out-of-sample performance with 10 repeats of stratified 5-fold CV. Each outer fold fits one progressive `H = 6` model, evaluates `H = 3:6`, and keeps the outer test subjects untouched by centering, response recoding, GCV, thresholds, score scaling, and SVM fitting.
- Compare the paper response loading and the SVM slider loading across distinct outer training fits with fixed CTRL orientation and tetrahedral FEM mass correlations. No post-hoc sign flip is used.
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

The H=6 run supplies the sensitivity analysis without a second fit. For each prefix `H = 3:6`, the aggregation standardizes the retained scores, fits a linear maximum-margin boundary, and verifies perfect in-sample separation. Positive scores follow the paper's response convention and denote CTRL. The primary interpretation map is the X-reconstruction loading for a one-unit slider displacement along the standardized maximum-margin axis, `f_H = R_H D_H q_H`, where `D_H` contains the score standard deviations and `q_H` is the unit SVM normal. The functional coefficient that directly implements the classifier is retained only as a predictive control. Both are compared with their `H = 3` references using the tetrahedral FEM mass correlation. The historical response-loading rotation and native regression coefficient comparison remain available as separate diagnostics. A native failure is recorded in the aggregate status and returned as a nonzero command status:

```sh
make run_test TEST_SUITE=brain TEST_NAME=h_stability
```

In a second terminal, inspect or follow the native progress log:

```sh
make h_stability_logs
make h_stability_tail
```

The helpers follow H=6 by default.

Completed diagnostics are written to `results/brain/aggregate/h_stability/`:
`separation_by_H.csv`, `maximum_margin_sensitivity_by_H.csv`,
`maximum_margin_spatial_stability_by_H.csv`, `maximum_margin_boundaries_by_H.csv`,
and the coefficient maps under `maximum_margin_maps/`. Margin and correlation figures are
written under `images/brain/aggregate/h_stability/`.

The `paraview/` subdirectory contains one tetrahedral VTU with raw and comparison-normalized
`beta`, `gamma`, and `f` fields for `H = 3:6`. Its Python scene arranges the fields as three
rows by four component-prefix columns, uses linked cameras, and writes a reusable `.pvsm`
state when run:

```sh
paraview --script=results/brain/aggregate/h_stability/paraview/maximum_margin_comparison.py
```

The scene uses response-oriented, FEM-mass-normalized fields for shape comparison; the same
VTU retains the unnormalized coefficient arrays.

## Out-Of-Sample Analysis

The production study creates 50 independent outer fits: 5 stratified folds by 10 repeats.
Every subject receives one held-out prediction per repeat. `H = 3` is the primary analysis;
`H = 4:6` is a declared sensitivity analysis and is not selected using the held-out data.

Two classifiers are reported. The first reconstructs the scalar fPLS response and learns its
threshold on the outer training set. The second is an inverse-frequency-weighted linear SVM
in standardized fPLS score space, with its cost selected using only outer-training data.
Held-out scores are computed by the same sequential projection and deflation used by native
fPLS, rather than by multiplying the data by an unrelated coefficient vector.

Run the two-fit, one-component plumbing check locally:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=out_of_sample
```

Production outputs are written to `results/brain/aggregate/out_of_sample/`. They include
fold and pooled out-of-fold metrics, subject predictions, selected lambdas, SVM tuning,
wall time and peak RAM, and cross-fit loading correlations. The primary imbalance-aware
metrics are SCHZ sensitivity, SCHZ average precision, SCHZ ROC AUC, CTRL specificity,
balanced accuracy, and MCC. Quantiles across the 10 repeats describe split variability;
they are not formal confidence intervals.

## Torque Cluster

The `hpc-torque` profile is aligned with canonical testbench runtime commit
`89ba803b85c76b40aab8af2037b779fd29677924`. It submits compilation, distributes option
files across PBS workers, exports the configured environment, and schedules aggregation
with an `afterok` dependency. Each fPLS fit is single-threaded; independent outer folds run
in parallel.

```sh
TESTBENCH_PATH_APPLICATION_DATA=/cluster/path/to/brain-data make build PROFILE=hpc-torque
make run_test TEST_SUITE=brain TEST_NAME=out_of_sample
```

The application defaults to at most 15 workers, one CPU and 16 GB per worker, with a
12-hour wall-time request. `PBS_MAX_JOBS=50` requests one worker per fit when the scheduler
policy permits it. `PBS_QUEUE`, `PBS_ACCOUNT`, `PBS_MEM`, and `PBS_TIME` are available as
run-time overrides. Preview submissions with `PBS_DRY_RUN=1`.

See [docs/provenance.md](docs/provenance.md) for source, template, native-stack, and data-provenance details.
