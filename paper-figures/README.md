# Application figure sources

The tracked Affinity layout is `layouts/figures.af`. Generated panel and export directories are ignored by Git.

Two scripts reconstruct the application panels from the complete-data R1-fPLS result:

- `scripts/A_latent_scores.R` verifies the recorded `H = 3` intrinsic coordinates and threshold, then produces the latent-score panels.
- `scripts/A_slider.R` verifies the recorded complete-data intrinsic loading and calls `scripts/A_slider.py` through ParaView to render SCHZ, threshold, and CTRL connectivity states.

Run both with:

```sh
make application_figure_panels
```

Set `FPLS_RESULTS` when the result store is not available as `results/`. The latent-score script requires `ggplot2`, `plotly`, `htmlwidgets`, Google Chrome, and ImageMagick. The slider script requires ParaView and accepts its Python executable through `PVPYTHON`.

The scripts read the native scores and loadings plus these aggregate sources:

```text
results/brain/aggregate/h_stability/intrinsic_fpls_scores_H3.csv
results/brain/aggregate/h_stability/intrinsic_fpls_slider_maps/reconstruction_loading_h3.csv
```
