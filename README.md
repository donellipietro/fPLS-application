# fPLS Neuroimaging Application

This repository ports the fPLS resting-state fMRI connectivity application to the current native fdaPDE C++ implementation. It is scoped to the reviewer-facing application analysis, not to the historical simulation suites.

The application compares control and schizophrenia groups using imputed brain connectivity maps on a volumetric tetrahedral mesh. The response is the historical CNTRL-vs-SCHZ binary contrast recoded with prevalence weights. The empirical overall predictor mean is smoothed on the tetrahedral P1 finite-element space and calibrated by GCV before centering. The complete-data fit uses all subjects for that mean; every outer-CV fit estimates it from its training subjects only. The historical script's accidental overwrite from `overall_mean` to `group_means` is not preserved as active behavior.

## Analysis Scope

- Fit native R1-fPLS and an fdaPDE-smoother-based fPCR comparator on the same 3D brain mesh, functionally centered data, component prefixes, and regularization grid. The application controls functional-mean, fPLS, and fPCA GCV probe counts and seeds explicitly.
- Use the application-expanded GCV grid `10^(-15:2)` for the functional mean, fPLS, and fPCA. It contains the simulation grid and the historical mean value `1e-2`; its lower extension follows controlled H=6 runs selecting `1e-9` and then `1e-12` for fPLS loading 2. A production boundary selection is warned, recorded, and labelled in run status without terminating the analysis. For each boundary-selected fPLS loading, the native fit saves the full candidate-wise GCV curve plus both the fitted selection and the replayed numerical minimum in `fpls_loading_gcv.csv`; a replay difference is diagnostic and nonfatal.
- Fit a single sequential `H = 6` model and report prefix-wise separation diagnostics for `H = 3:6`; `H = 3` remains the exploratory setting to be verified as the first prefix with perfect in-sample separation.
- Use fPLS for dimension reduction, then estimate the maximum-margin linear boundary in each standardized score prefix `H = 3:6`. This is an in-sample exploratory boundary, not a cross-validated diagnostic classifier.
- Map each score-space boundary to both its reconstructed connectivity pattern and its exact functional classifier coefficient, then compare both maps with their `H = 3` references using tetrahedral FEM mass correlations.
- Estimate out-of-sample performance with 10 repeats of stratified 5-fold CV. Each outer split fits progressive `H = 6` R1-fPLS and fPCR reducers, evaluates `H = 3:6`, and keeps the outer test subjects untouched by centering, response recoding, GCV, latent-response regression, thresholds, score scaling, and SVM fitting.
- Compare latent-response and SVM slider loadings across distinct outer training fits within each dimension reducer, with fixed CTRL orientation and tetrahedral FEM mass correlations. No post-hoc sign flip or cross-reducer mixing is used.
- Record selected fPLS/fPCA lambdas, component iterations, objective/monotonicity diagnostics, non-finite/failure status, wall-clock time, peak RAM, input and native-binary MD5 checksums, runtime profile, and exact fdaPDE commits.

Raw brain data and generated outputs are intentionally outside Git. The default local data path is the historical ignored application input folder:

```sh
/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain
```

Override it with `PATH_APPLICATION_DATA=/path/to/brain-data`.

The native fdaPDE stack is cloned locally into the ignored `libraries/fdaPDE-cpp` directory on `develop_fPLS`; the application does not run against the simulation repository checkout.

## Minimal Local Workflow

Write the profile and create generated directories:

```sh
PATH_FDAPDE_CPP=/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp \
FDAPDE_CPP_MANAGED=false \
Rscript config.R --profile macbook --write-env

Rscript config.R --profile macbook --create-dirs
```

Compile the native 3D driver:

```sh
make compile MODEL=brain TARGET=fit_model
```

Run the non-expensive application smoke check, which validates and records raw input preparation but skips the native functional-mean and model fits:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=smoke_overall_mean
```

The H=6 run supplies the sensitivity analysis without a second fit. For each prefix `H = 3:6`, the aggregation standardizes the retained scores, fits a linear maximum-margin boundary, and verifies perfect in-sample separation. Positive scores follow the paper's response convention and denote CTRL. The primary interpretation map is the X-reconstruction loading for a one-unit slider displacement along the standardized maximum-margin axis, `f_H = R_H D_H q_H`, where `D_H` contains the score standard deviations and `q_H` is the unit SVM normal. The functional coefficient that directly implements the classifier is retained only as a predictive control. Both are compared with their `H = 3` references using the tetrahedral FEM mass correlation; native beta is compared separately with beta at `H = 3`. A native failure is recorded in the aggregate status and returned as a nonzero command status:

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

The production study creates 50 independent outer splits: 5 stratified folds by 10 repeats,
with one R1-fPLS and one fPCR fit per split (100 native reducer fits in total).
Every subject receives one held-out prediction per repeat. `H = 3` is the primary analysis;
`H = 4:6` is a declared sensitivity analysis and is not selected using the held-out data.

The comparison has two explicit axes. The dimension reducer is either R1-fPLS or fPCR; the
downstream classifier is either training-only OLS of the recoded response on the retained
scores, with a training threshold, or an inverse-frequency-weighted linear SVM tuned only on
outer-training data. Both reducers export a sequential held-out score transform that is checked
against their native training scores. For fPCR, each fPCA loading is paired with a training-only
projection scale before the same residual deflation is applied to training and held-out subjects.
SVM cost tuning is classifier-only inner CV conditional on the reducer fitted to the complete
outer-training fold; it is not nested CV of the entire supervised fPLS pipeline. The outer test
fold remains untouched, so reported out-of-fold performance still evaluates the fitted pipeline,
but this conditional tuning should not be presented as an unbiased inner estimate.

Run the two-fold, one-component plumbing check locally (four native reducer fits). It uses reduced probe counts and iteration limits but still exercises GCV; it does not fix lambda to `1e-9`:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=out_of_sample
```

Production outputs are written to `results/brain/aggregate/out_of_sample/`. They include
fold and pooled out-of-fold metrics, subject predictions, separate fPLS/fPCA lambdas, SVM tuning,
wall time, peak RAM when the runtime permits measurement, its explicit availability status,
and cross-fit loading correlations. The primary imbalance-aware
metrics are SCHZ sensitivity, SCHZ average precision, SCHZ ROC AUC, CTRL specificity,
balanced accuracy, and MCC. Quantiles across the 10 repeats describe split variability;
they are not formal confidence intervals. `application_run_status.json` reports
`smoke_complete` for the reduced plumbing check and currently reports
`production_complete` only for the full saved canonical protocol. Non-smoke overrides that
change the canonical 10-by-5 design report `noncanonical_complete` instead of claiming
production completion.

## Torque Cluster

The `hpc-torque` profile is the Kami runtime and is aligned with canonical testbench runtime commit
`89ba803b85c76b40aab8af2037b779fd29677924`. It submits compilation, distributes option
files across PBS workers, exports the configured environment, and schedules aggregation
with an `afterok` dependency. Each fPLS/fPCR fit is single-threaded; independent outer folds run
in parallel. The managed cluster clone is pinned to outer commit
`ecbf23ef37571174c438ab68c3d21d7ecd5cf18f` and core commit
`1b75249a7b49ccee72cb94207a9dc5daaa21848c` on their mapped fPLS branches.

```sh
PATH_APPLICATION_DATA=/cluster/path/to/brain-data make build PROFILE=hpc-torque
make run_test TEST_SUITE=brain TEST_NAME=h_stability
# After h_stability aggregation completes successfully:
make run_test TEST_SUITE=brain TEST_NAME=out_of_sample
```

Production fits require a clean committed application worktree. Preview the compile, queue partitioning, PBS resources, and dependent aggregation jobs without submission:

```sh
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=h_stability
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=out_of_sample
```

The application defaults to at most 15 workers, one CPU and 16 GB per worker, with a
12-hour wall-time request. `PBS_MAX_JOBS=50` requests one worker per outer split (each runs
the two reducers sequentially) when the scheduler
policy permits it. `PBS_QUEUE`, `PBS_ACCOUNT`, `PBS_MEM`, and `PBS_TIME` are available as
run-time overrides. Preview submissions with `PBS_DRY_RUN=1`.

See [docs/provenance.md](docs/provenance.md) for source, template, native-stack, and data-provenance details.
