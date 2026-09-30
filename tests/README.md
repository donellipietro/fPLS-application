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
`images/brain/aggregate/<TEST_NAME>/`. To reproduce the supplementary comparison across all
retained component counts from the saved six-component resampling fits:

```sh
Rscript tests/brain/postprocess_slider_resampling_by_H.R results results/brain/aggregate/slider_resampling_by_H
```

If results are stored elsewhere, replace the first `results` argument with the directory
containing `brain/`. The resulting `summary_by_H.csv` contains the median and quartiles of slider similarity
(`rho_H`) for both references: the complete-data `H = 3` slider and each fold's own `H = 3`
slider. The 50 overlapping training sets provide descriptive stability summaries.

See [figure sources](../paper-figures/README.md) for the application panels.
