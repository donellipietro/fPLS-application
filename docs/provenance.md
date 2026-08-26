# Provenance

This repository is the reviewer-facing fPLS neuroimaging application port.

## Template

- Canonical template: `/Users/pietrodonelli/Documents/University/fdaPDE/fdaPDE-test-bench`
- Template remote recorded locally as: `template`
- Imported commit: `167e8c2ec240e0f247a1853cbe61e9b7d7e3890a`
- Imported scope: runtime profiles, Makefile runner, C++ compile/run helpers, shared `src/` utilities, runner scripts, and testbench documentation
- PBS/Torque runtime alignment: canonical template commit `89ba803b85c76b40aab8af2037b779fd29677924` (`Export environment to PBS test jobs`)

The application repository is not the template repository. The template is retained as provenance only.

## Historical Application Source

- Source repository: `/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression`
- Source commit: `7fb91720b97661c8f83f675f8915ac96f7465912`
- Primary workflow inventoried: `analysis/main_CNTRLvsSCHZ.R`
- Supporting workflow inventoried: `analysis/sensitivity_analysis.R`

Historical simulation suites are intentionally not migrated here.

## Native Stack

- fdaPDE-cpp branch: `develop_fPLS`
- Expected outer commit: `ecbf23ef37571174c438ab68c3d21d7ecd5cf18f`
- Expected core gitlink: `1b75249a7b49ccee72cb94207a9dc5daaa21848c`
- Application runtime checkout: `libraries/fdaPDE-cpp` (ignored and managed locally)
- Local bootstrap source: `/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp`
- The `hpc-torque` managed clone verifies and checks out the expected outer/core commits rather than following a later branch tip.

The native application driver uses the fdaPDE C++ `fPLS` implementation. Its fPCR comparator
implements the same native fPCA power-iteration equations locally around the fdaPDE elliptic
smoother so the application can pass the configured Hutchinson probe count and seed explicitly
to `edf()`. This avoids the pinned generic fPCA wrapper's implicit stochastic defaults without
modifying the ignored dependency checkout. Telemetry records the exact implementation mode,
probe count, seed, initialization, and selected lambdas. The application does not use the
obsolete `fPLS-R`/`fdaPDE2` wrapper.

## Application Data

Raw and imputed brain data are external to Git. The default local data path is:

`/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain`

Override it with `PATH_APPLICATION_DATA=/path/to/brain-data` before writing the profile `.env` or running the suite.

The expected local files are:

- `FEMbasis.Rds`
- `X_imputed.rds`
- `Ycl.rds`

The response recoding is preserved from the historical workflow after relabeling `CONTROL` to `CTRL`:

- `CTRL`: `sqrt(p_SCHZ / p_CTRL)`
- `SCHZ`: `-sqrt(p_CTRL / p_SCHZ)`

The active centering family is the authoritative GCV-smoothed overall functional mean. The
native driver first computes the nodewise empirical mean over its training rows, smooths that
mean in the tetrahedral P1 finite-element space with the gradient penalty, and subtracts the
fitted nodal mean from every predictor row. The complete-data run supplies all subjects; each
resampling fit supplies its training subset only. The mean is selected by genuine GCV over the application-expanded grid
`10^(-15:2)`, which contains the simulation grid and archived `1e-2` value. The lower extension
was triggered by controlled H=6 runs selecting the former `1e-9` and `1e-12` lower boundaries
for fPLS loading 2. The grid, seed, probe count, EDF, GCV score, selected
lambda, coefficients, and nodal fitted mean are exported. The historical script's later overwrite to `group_means` is not
ported as active behavior.

R1-fPLS uses that same GCV grid. Smoke resampling also
uses GCV, with reduced probes and iteration limits; the fixed `1e-9` smoke shortcut is no longer
active. Production evaluation warns on any functional-mean, fPLS, or fPCA selection at a grid
boundary, continues the analysis, labels the completed run status accordingly, and exports the
complete boundary diagnostic table. For each boundary-selected fPLS loading, the native
driver replays the loading GCV calculation on its sequential residual and saves every candidate's
lambda, EDF, GCV score, fitted-selection flag, and replay-minimum flag in
`fpls_loading_gcv.csv`. A replay difference is recorded in telemetry and the native log but is
nonfatal, because the fitted model remains the authoritative result.

Every fit records the clean application commit, MD5 checksums for the three input RDS files and the compiled native driver.
Cached prepared data and native fits are reused only when those checksums, the preprocessing
implementation, the full fit configuration, the split, and the outer and core fdaPDE commits
match.

## Component And Sampling-Stability Diagnostics

The exploratory application run requests one sequential `H = 6` fit and evaluates prefixes at `H = 3:6`. This reports in-sample separation and spatial sensitivity within that fit.

The complete-data fit also reports the observation-location Frobenius proportions of reconstructed
X variance, Y variance, and X--Y cross-covariance for `H = 1:6`, matching the simulation-study
definitions. The FEM mass matrix is intentionally not used for these local-observation diagnostics;
it remains the metric for comparing functional slider maps.

The sampling-stability study uses 10 repeats of stratified five-fold delete-one-fold resampling.
One sequential `H = 6` R1-fPLS model is fitted per training subset. Labels define the stratified
assignment; omitted predictors and labels are excluded from fitting and slider construction.
Each training fit re-estimates its
functional mean, prevalence-weighted response, GCV penalties, and score standardization, checks the
first perfectly separating prefix, and constructs the H=3 slider with fixed `C = 1e6`. Its
CTRL-oriented map is compared with the accepted complete-data H=3 slider using tetrahedral P1 FEM
mass correlation and relative mass error, without post-hoc sign alignment. Because the full-data
reference overlaps every training subset, this is descriptive resampling stability rather than
independent validation or predictive performance.

The optional fPCR comparator repeats the same split indices and slider construction in separate
`fpcr_h_stability` and `fpcr_slider_resampling` targets. Each fPCR training slider is compared only
with the complete-data fPCR H=3 slider. fPCR and R1-fPLS maps are never treated as interchangeable;
their resampling summaries can be contrasted as paired method-specific stability diagnostics.
Because fPCR does not use Y to choose its components, H=3 hard-margin separation is recorded rather
than required, and any fixed-cost soft-margin slider is labelled accordingly.

Both slider-resampling targets post-process their saved training-only models on the corresponding
omitted fold. Test predictors are centered and projected with training-fitted quantities; test
responses use the training-fold prevalence coding, and no test quantity affects fitting, GCV,
component construction, or slider definition. For each repeat, fold, and H=1:6, the post-processing
reports observation-location Frobenius X variance, Y variance, and X--Y cross-covariance explained.
The 50 fold curves are descriptive repeated-split diagnostics and are not independent replicates;
negative held-out explained values are retained rather than truncated.
