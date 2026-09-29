# Application figure sources

The tracked Affinity layout is [layouts/figures.af](layouts/figures.af). Generated panel and export directories are ignored by Git.

Two scripts reconstruct the article's latent-score and functional-connectivity panels from the complete-data R1-fPLS result:

- [A_latent_scores.R](scripts/A_latent_scores.R) verifies the recorded `H = 3` intrinsic coordinates and threshold, then produces the latent-score panels.
- [A_slider.R](scripts/A_slider.R) verifies the recorded complete-data intrinsic loading and calls [A_slider.py](scripts/A_slider.py) through ParaView to render SCHZ, threshold, and CTRL connectivity states.

## Prerequisites

Install the following on your machine to generate the panels:

- R with Cairo PDF support and Arial;
- Google Chrome for the latent-score rendering;
- ParaView with `pvpython` for the connectivity maps;
- ImageMagick with `magick` on `PATH` for both renderers.

The R packages `ggplot2`, `plotly`, and `htmlwidgets` are installed automatically by
`make build`, as described in the [root README](../README.md).

## Generate panels

After running `h_stability` as described in the [analysis guide](../tests/README.md),
run both scripts from the repository root with:

```sh
make application_figure_panels
```

The scripts read `results/` by default. For a different result directory, use:

```sh
FPLS_RESULTS=/absolute/path/to/results make application_figure_panels
```

Set `GOOGLE_CHROME` to the Chrome executable if it is outside the default macOS path.
If `pvpython` is not on `PATH`, pass `PVPYTHON=/path/to/pvpython` to the Make command.

The scripts read the native scores and loadings plus these aggregate sources:

```text
results/brain/aggregate/h_stability/intrinsic_fpls_scores_H3.csv
results/brain/aggregate/h_stability/intrinsic_fpls_slider_maps/reconstruction_loading_h3.csv
```

Both scripts also require `prepared_data.rds` and the native fit files below
`results/brain/h_stability/h_stability_H6/batch_1/`. Panels are written to
`paper-figures/panels/A_latent_scores/` and `paper-figures/panels/A_slider/`.
The manuscript figures are assembled and exported from `layouts/figures.af` using Affinity.
