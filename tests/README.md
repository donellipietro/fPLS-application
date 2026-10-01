# Neuroimaging analyses

The analyses in `brain/` support the article's functional-connectivity application and the
Supplementary Material's intrinsic-slider derivation and stability table.

| TEST_NAME | Article or Supplementary Material output |
| --- | --- |
| `h_stability` | Complete-data R1-fPLS fit, separation across `H = 1:6`, intrinsic-slider figures, and slider similarity relative to `H = 3` |
| `slider_resampling` | 50 training fits from ten repeated stratified five-fold splits, first separating prefix, and slider stability |
| `fpcr_h20_separation` | Exploratory fPCR comparison through `H = 20` |

After completing the setup in the [root README](../README.md), run from the repository root.
`make run_test` automatically compiles the analysis and reuses the profile saved in `.env`:

```sh
# Fit the complete-data R1-fPLS model and compare component prefixes
make run_test TEST_SUITE=brain TEST_NAME=h_stability

# Evaluate slider stability with 50 resampling fits
make run_test TEST_SUITE=brain TEST_NAME=slider_resampling

# Fit the complete-data fPCR comparator through H = 20
make run_test TEST_SUITE=brain TEST_NAME=fpcr_h20_separation
```

Run `h_stability` before `slider_resampling`: the latter uses the complete-data `H = 3` slider
as its reference. Each resampling fit re-estimates preprocessing and regularization using
only its training subjects.

Aggregates are written to `results/brain/aggregate/<TEST_NAME>/` and figures to
`images/brain/aggregate/<TEST_NAME>/`. After completing `h_stability` and `slider_resampling`,
generate the supplementary comparison across all retained component counts:

```sh
make application_paper_tables
```

The CSV table is written to `paper-tables/csv/`. It combines the complete-data similarity
with the median and quartiles across the 50 training fits, using both the complete-data
`H = 3` slider and each fold's own `H = 3` slider as references. See the
[table guide](../paper-tables/README.md) for inputs, outputs and an alternative results directory.
The 50 overlapping training sets provide descriptive stability summaries.

See [figure sources](../paper-figures/README.md) for the application panels.

## Run the complete application on Kami

From the repository root on Kami, load your compiler and R environment and place the three
private inputs in `data/brain`, or export `PATH_APPLICATION_DATA` with their directory. Then run:

```sh
# Submit all application analyses and the supplementary CSV table on one exclusive node
make kami_review_submit
```

The script selects a completely idle node with the paper's 96 logical CPUs and at least
500 GiB of RAM, and verifies its AMD EPYC 7413 processor before starting. It configures
`hpc-torque`, builds the native driver, and runs `h_stability`, the 50 `slider_resampling`
fits, and `fpcr_h20_separation` sequentially, with one computational thread per fit.
Each analysis is aggregated before the next starts; the supplementary CSV table is generated
after all analyses complete. Manuscript panels can then be generated locally from the saved fits.

The default request is four CPUs, 32 GB RAM, and 72 hours in the `test` queue, with
`place=excl`. Override `PBS_MULTI_CPUS`, `PBS_MULTI_MEM`, `PBS_MULTI_TIME`, or `PBS_QUEUE`
when submitting. Preview the request without submitting with `make kami_review_submit PBS_DRY_RUN=1`.
The job identifier, output, errors, hardware description, and final status are saved under
`logs/kami/<run-tag>/`.
