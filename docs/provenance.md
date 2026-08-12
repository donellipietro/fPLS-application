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

The active centering family is the authoritative `overall_mean` family: the complete-data run
uses the overall mean of all subjects, while each outer-CV fit estimates that same kind of mean
from its training subjects only. The historical script's later overwrite to `group_means` is not
ported as active behavior.

Every fit records MD5 checksums for the three input RDS files and the compiled native driver.
Cached prepared data and native fits are reused only when those checksums, the preprocessing
implementation, the full fit configuration, the split, and the outer and core fdaPDE commits
match.

## Component And Out-Of-Sample Diagnostics

The exploratory application run requests one sequential `H = 6` fit and evaluates prefixes at `H = 3:6`. This reports in-sample separation and spatial sensitivity within that fit.

The out-of-sample study uses 10 repeats of stratified 5-fold CV. One sequential `H = 6`
R1-fPLS model and one sequential `H = 6` fPCR model are fitted per outer training fold; their
`H = 3:6` prefixes are evaluated without separate prefix refits. The training functional mean,
prevalence-weighted response, GCV-selected lambdas, latent-response OLS, threshold, score
standardization, and weighted linear SVM are estimated without outer-test subjects. Both native
reducers export sequential residual projections and must reproduce their exported training scores
to numerical tolerance before held-out evaluation proceeds.

Loading reproducibility is a distinct-fit comparison. Within each repeat and dimension reducer,
the latent-response loading and SVM slider loading are compared pairwise across the five outer
training fits using the tetrahedral P1 FEM mass correlation. Both retain their training-derived
CTRL-positive orientation; no post-hoc sign alignment is applied and reducers are never pooled.
