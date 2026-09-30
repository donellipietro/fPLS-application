# Provenance

## Historical application

The application equations, response coding, and data layout originate from:

- legacy repository: `fPLS-regression`
- revision: `7fb91720b97661c8f83f675f8915ac96f7465912`
- primary workflow: `analysis/main_CNTRLvsSCHZ.R`
- supporting workflow: `analysis/sensitivity_analysis.R`

The active centering method is the GCV-smoothed overall functional mean.

## Native stack

The expected native dependencies are:

- fdaPDE-cpp branch: `develop_fPLS`
- fdaPDE-cpp revision: `fbf764fafe81d21d3a25f89c5f53f65c7cee8514`
- fdaPDE core branch: `codex/fpls-stable-parser` (stable plus the table-reader path fix)
- fdaPDE core revision: `472f9bd374a63fbf851106e5c45f8870e31e8189`

The managed checkout lives in the ignored `libraries/fdaPDE-cpp` directory. Setting `FDAPDE_CPP_MANAGED=false` uses `PATH_FDAPDE_CPP` without changing that checkout.

The R1-fPLS driver uses the native fdaPDE implementation. The fPCR comparator implements the corresponding fPCA power iteration around the same elliptic smoother so the Hutchinson probe count and seed are explicit. Telemetry records the implementation mode, selected regularization, iterations, objective diagnostics, and resource use.

## Data and preprocessing

The private preprocessed inputs are not distributed with this repository. Their frozen checksums are:

| File | MD5 |
| --- | --- |
| `FEMbasis.Rds` | `59433e991190b029f6f190b00c4f878a` |
| `X_imputed.rds` | `bf40b1320a4b0b115117d922ac2d08c3` |
| `Ycl.rds` | `e99aba962f10e0384d1897365a028bca` |

The response is relabelled from `CONTROL` to `CTRL` and coded as:

- `CTRL`: `sqrt(p_SCHZ / p_CTRL)`
- `SCHZ`: `-sqrt(p_CTRL / p_SCHZ)`

For every fit, the empirical predictor mean is estimated from that fit's rows, smoothed in the tetrahedral P1 finite-element space, and subtracted at mesh nodes. Complete-data targets use all subjects. Resampling targets use only the selected training subset; omitted predictors and labels are not retained in the fit input.

The standard functional-mean and R1-fPLS GCV grid is `10^(-15:2)`. The fPCR `H = 20` target extends only the fPCA grid to `10^(-15:6)`. Probe counts and seeds are explicit. Candidate-wise fPLS loading and fPCA GCV diagnostics are exported where applicable. A boundary selection is recorded in the aggregate status.

## Intrinsic slider and threshold

For prefix `H`, score standard deviations form the diagonal matrix `D_H`. With X loadings `R_H` and response loadings `nu_H`, the standardized intrinsic direction is

```text
q_H = D_H nu_H / ||D_H nu_H||,
```

and its functional loading is

```text
f_H = R_H D_H q_H.
```

The implementation stores the score center, score scale, unit standardized normal, response norm, subject coordinate, and functional loading. The exact response threshold maximizes sensitivity plus specificity over observed oriented fitted values. Its `H = 3` standardized coordinate is saved in `intrinsic_fpls_scores_H3.csv`.

Spatial comparisons use the tetrahedral P1 finite-element mass inner product. `H = 1:6` intrinsic loadings (including the reference itself) are compared against the `H = 3` reference without post-hoc sign alignment. All prefixes are reconstructed from the saved complete-data `H = 6` fit; adding `H = 1:2` requires no refit.

## Sampling stability

The sampling target uses 10 repeats of stratified five-fold delete-one-fold sampling. It fits one progressive `H = 6` R1-fPLS model on each of 50 training subsets. Each fit independently estimates its functional mean, prevalence-weighted response, GCV penalties, score standardization, first perfectly separating prefix, and intrinsic `H = 3` slider.

Each training slider is compared with the complete-data `H = 3` slider using FEM mass correlation and relative mass error. The complete-data reference overlaps each training subset, so the resulting distribution is a descriptive stability measure rather than an independent replication.

## Recorded identity

Each native fit records:

- application revision and clean-worktree status
- native binary MD5
- input-file MD5 values
- preprocessing identity
- complete fit configuration and resampling indices
- fdaPDE-cpp and core revisions
- runtime profile
- wall time and peak RAM

Prepared data and native fits are reused only when their recorded identity matches the requested configuration.
