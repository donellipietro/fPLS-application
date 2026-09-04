# Brain application suite

The `brain` suite is controlled by `tests/brain/config.R` and exposes exactly four targets:

```text
smoke_overall_mean
h_stability
slider_resampling
fpcr_h20_separation
```

`src/init.R` generates JSON options in `tmp/queue/brain/<target>/`. A runner invokes `tests/brain/main.R` once per option and then calls `tests/brain/aggregate_results.R`.

The principal files are:

```text
tests/brain/
├── config.R
├── main.R
├── aggregate_results.R
├── test_fpcr_h20_options.R
├── test_slider_resampling.R
└── utils/
    ├── data_prep.R
    ├── fit_and_evaluate.R
    ├── generate_options.R
    ├── intrinsic_slider.R
    ├── loading_stability.R
    ├── models_evaluation.R
    ├── paraview_export.R
    ├── projection.R
    ├── slider_resampling.R
    └── wrappers.R
```

Use the root Makefile for normal execution:

```sh
make run_test TEST_SUITE=brain TEST_NAME=h_stability
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
```

The reduced resampling path uses two folds and three components:

```sh
SMOKE_TEST=1 make run_test TEST_SUITE=brain TEST_NAME=slider_resampling
```

Lightweight unit checks do not read private application data or run native fits:

```sh
Rscript tests/brain/test_slider_resampling.R
Rscript tests/brain/test_fpcr_h20_options.R
```
