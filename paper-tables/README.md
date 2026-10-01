# Manuscript table sources

`scripts/generate_slider_similarity_table.R` generates the CSV supporting the Supplementary
Material's table “Cosine similarity of the functional slider across retained component counts”
and the slider-stability statements in the article.

Follow the [setup and execution instructions](../README.md#setup-and-execution), then run
`h_stability` and `slider_resampling` as described in the [analysis guide](../tests/README.md).
The generator requires the complete-data six-component fit, all 50 six-component training
fits, the reference mesh, the complete-data `H = 3` slider map and the aggregated resampling comparisons.

From the repository root, generate the table with:

```sh
make application_paper_tables
```

The target loads `.env` when present, including the configured R library paths, and reads
`results/` by default. To use results stored elsewhere:

```sh
FPLS_RESULTS=/absolute/path/to/results make application_paper_tables
```

The results directory must contain `brain/` with the raw fits and aggregates of both analyses.
The generator reconstructs each prefix slider from the saved scores and loadings and compares
it using the tetrahedral FEM mass inner product, preserving its CTRL orientation. It checks
the 50 archived `H = 3` comparisons and each fold's `H = 3` self-comparison.

Generated files are saved in `paper-tables/csv/`, relative to the repository root:

- `slider_similarity.csv`: six rows for `H = 1,…,6`, combining the complete-data similarity
  with the training-fold median and quartiles for each of the two `H = 3` references;
- `summary_by_H.csv`: descriptive summaries of cosine similarity (`rho_H`) and relative
  mass-norm error (`e_H`) for both training-fold references;
- `comparisons_by_fold_and_H.csv`: the 600 individual prefix comparisons;
- `saved_fit_inputs.csv`: the input paths and checksums used to generate the table.

The CSV files retain full numerical precision. The manuscript presents cosine similarities
to three decimal places and uses the training-fold median with its interquartile range.
The overlapping training sets provide descriptive stability summaries, rather than
50 independent experiments. The manuscript contains formatted values and is not edited
by the generator. Generated CSV files are ignored by Git and removed by `make distclean`.
