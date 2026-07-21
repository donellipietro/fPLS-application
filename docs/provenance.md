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

The native application driver uses the new fdaPDE C++ `fPLS` implementation. It does not use the obsolete `fPLS-R`/`fdaPDE2` wrapper.

## Application Data

Raw and imputed brain data are external to Git. The default local data path is:

`/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain`

Override it with `TESTBENCH_PATH_APPLICATION_DATA=/path/to/brain-data` before writing the profile `.env` or running the suite.

The expected local files are:

- `FEMbasis.Rds`
- `X_imputed.rds`
- `Ycl.rds`

The response recoding is preserved from the historical workflow after relabeling `CONTROL` to `CTRL`:

- `CTRL`: `sqrt(p_SCHZ / p_CTRL)`
- `SCHZ`: `-sqrt(p_CTRL / p_SCHZ)`

The active centering family is the authoritative `overall_mean` family. The historical script's later overwrite to `group_means` is not ported as active behavior.

## Component And Out-Of-Sample Diagnostics

The exploratory application run requests one sequential `H = 6` fit and evaluates prefixes at `H = 3:6`. This reports in-sample separation and spatial sensitivity within that fit.

The out-of-sample study uses 10 repeats of stratified 5-fold CV. One sequential `H = 6` native model is fitted per outer training fold; its `H = 3:6` prefixes are evaluated without separate prefix refits. The training functional mean, prevalence-weighted response values, GCV-selected lambdas, response threshold, score standardization, and weighted linear SVM are all estimated without outer-test subjects. Test scores use the sequential residual projection defined by the native fPLS projection/deflation steps.

Loading reproducibility is a distinct-fit comparison. Within each repeat, the paper response loading and SVM slider loading are compared pairwise across the five outer training fits using the tetrahedral P1 FEM mass correlation. Both quantities retain their response-derived CTRL-positive orientation; no post-hoc sign alignment is applied.
