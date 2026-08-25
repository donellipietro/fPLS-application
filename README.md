# fPLS Neuroimaging Application

This repository ports the fPLS resting-state fMRI connectivity application to the current native fdaPDE C++ implementation. It is scoped to the reviewer-facing application analysis, not to the historical simulation suites.

The application compares control and schizophrenia groups using imputed brain connectivity maps on a volumetric tetrahedral mesh. The response is the historical CNTRL-vs-SCHZ binary contrast recoded with prevalence weights. The empirical overall predictor mean is smoothed on the tetrahedral P1 finite-element space and calibrated by GCV before centering. The complete-data fit uses all subjects for that mean; every resampling fit estimates it from its training subjects only. The historical script's accidental overwrite from `overall_mean` to `group_means` is not preserved as active behavior.

## Analysis Scope

- Fit native R1-fPLS and the fPCR comparator on the 3D brain mesh with functionally centered data, progressive component prefixes, and explicitly controlled GCV grids, probe counts, and seeds.
- Use the application-expanded GCV grid `10^(-15:2)` for the functional mean, fPLS, and fPCA. It contains the simulation grid and the historical mean value `1e-2`; its lower extension follows controlled H=6 runs selecting `1e-9` and then `1e-12` for fPLS loading 2. A production boundary selection is warned, recorded, and labelled in run status without terminating the analysis. For each boundary-selected fPLS loading, the native fit saves the full candidate-wise GCV curve plus both the fitted selection and the replayed numerical minimum in `fpls_loading_gcv.csv`; a replay difference is diagnostic and nonfatal.
- Fit a single sequential `H = 6` model, report prefix-wise reconstructed X variance, Y variance, and X--Y cross-covariance using the observation-location Frobenius definitions from the simulation study, and verify `H = 3` as the first prefix with perfect in-sample separation.
- Use the linear SVM only as a geometric construction on standardized fPLS scores. The primary interpretation map is the slider loading `f_H = R_H D_H q_H`; compare only `H = 4:6` with the `H = 3` reference through the tetrahedral FEM mass correlation `rho_H` and relative mass error `e_H`.
- Assess sampling stability with 10 repeats of stratified five-fold delete-one-fold resampling. Each training subset fits one progressive `H = 6` R1-fPLS model, rechecks the first perfectly separating prefix, constructs `f_3` with the same fixed `C = 1e6` rule, and compares it with the accepted complete-data `f_3`. Omitted subjects are not projected, predicted, or scored.
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

The H=6 run supplies the sensitivity analysis without a second fit. For each prefix `H = 3:6`, the aggregation standardizes the retained scores and fits a linear maximum-margin boundary with positive orientation toward CTRL. The primary interpretation map is the X-reconstruction loading for a one-unit slider displacement along the standardized maximum-margin axis, `f_H = R_H D_H q_H`, where `D_H` contains the score standard deviations and `q_H` is the unit SVM normal. Only `f_4`, `f_5`, and `f_6` are compared with `f_3`, using `rho_H` and `e_H`; no Gram--Schmidt basis is used. The same accepted fit also supplies observation-location Frobenius diagnostics for reconstructed X variance, Y variance, and X--Y cross-covariance. A native failure is recorded in the aggregate status and returned as a nonzero command status:

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
`separation_by_H.csv`, `explained_structure_by_H.csv`, `slider_stability_by_H.csv`,
`maximum_margin_sensitivity_by_H.csv`, `maximum_margin_boundaries_by_H.csv`,
and the slider maps under `maximum_margin_maps/`. Explained-structure and slider figures are
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

## Repeated Training-Sample Slider Stability

The reviewer-facing resampling study creates 50 training subsets: five stratified delete-one-fold
splits by ten repeats, with one progressive H=6 R1-fPLS fit per subset. Class labels are used to
construct the stratified fold assignment; after assignment, the omitted 20% defines the perturbation
only and its predictors and labels are not passed to the fit/evaluation path, projected, or used for
predictions or performance metrics.
Consequently this is descriptive sampling stability, not out-of-sample validation; the complete-data
reference overlaps each training subset.

Every fit re-estimates the functional mean, response coding, GCV penalties, score scaling, and
fixed-`C = 1e6` CTRL-oriented H=3 slider using its training subjects only. Aggregation reports the
distribution of the first perfectly separating training prefix and compares each available
training `f_3` with the complete-data `f_3` through FEM mass `rho_H3` and relative error `e_H3`.
The overlapping training subsets are descriptive resamples, not independent replicates.

Run the reduced two-fold, H=3 plumbing check locally:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
```

Production outputs are written to `results/brain/aggregate/slider_resampling/`. They include
fold diagnostics, the H-minimum distribution, every training-versus-complete slider comparison,
descriptive summaries, regularization/convergence provenance, and resource measurements.

The fPCR comparator uses two separate targets so it cannot overwrite or trigger refits of the
accepted R1-fPLS analysis. First fit and aggregate one complete-data H=6 fPCR reference, then run
the same 10-by-5 training subsets:

```sh
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h_stability
make run_test TEST_SUITE=brain TEST_NAME=fpcr_slider_resampling
```

The fPCR slider uses the same fixed-`C = 1e6` definition and FEM-mass `rho_H3`/`e_H3` metrics.
Hard-margin status is recorded rather than assumed: if H=3 is not linearly separable for fPCR, the
fixed-cost soft-margin slider remains comparable but is explicitly labelled as such.

## Torque Cluster

The `hpc-torque` profile is the Kami runtime and is aligned with canonical testbench runtime commit
`89ba803b85c76b40aab8af2037b779fd29677924`. It submits compilation, distributes option
files across PBS workers, exports the configured environment, and schedules aggregation
with an `afterok` dependency. Each fPLS fit is single-threaded; independent training folds run
in parallel. The managed cluster clone is pinned to outer commit
`ecbf23ef37571174c438ab68c3d21d7ecd5cf18f` and core commit
`1b75249a7b49ccee72cb94207a9dc5daaa21848c` on their mapped fPLS branches.

```sh
PATH_APPLICATION_DATA=/cluster/path/to/brain-data make build PROFILE=hpc-torque
make run_test TEST_SUITE=brain TEST_NAME=h_stability
# After h_stability aggregation completes successfully:
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
# Optional fPCR comparator, run in this order:
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h_stability
make run_test TEST_SUITE=brain TEST_NAME=fpcr_slider_resampling
```

Production fits require a clean committed application worktree. Preview the compile, queue partitioning, PBS resources, and dependent aggregation jobs without submission:

```sh
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=h_stability
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=fpcr_h_stability
PBS_COMPILE_DRY_RUN=1 PBS_DRY_RUN=1 make run_test TEST_SUITE=brain TEST_NAME=fpcr_slider_resampling
```

The application defaults to at most 15 workers, one CPU and 16 GB per worker, with a
12-hour wall-time request. `PBS_MAX_JOBS=50` requests one worker per training split when the scheduler
policy permits it. `PBS_QUEUE`, `PBS_ACCOUNT`, `PBS_MEM`, and `PBS_TIME` are available as
run-time overrides. Preview submissions with `PBS_DRY_RUN=1`.

See [docs/provenance.md](docs/provenance.md) for source, template, native-stack, and data-provenance details.
