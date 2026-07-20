# Provenance

This repository is the reviewer-facing fPLS neuroimaging application port.

## Template

- Canonical template: `/Users/pietrodonelli/Documents/University/fdaPDE/fdaPDE-test-bench`
- Template remote recorded locally as: `template`
- Imported commit: `167e8c2ec240e0f247a1853cbe61e9b7d7e3890a`
- Imported scope: runtime profiles, Makefile runner, C++ compile/run helpers, shared `src/` utilities, runner scripts, and testbench documentation

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
- Clean local reference checkout: `/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp`

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

## Component Diagnostics

The initial native application run requests one sequential `H = 6` fit and evaluates the fitted-response prefixes at `H = 3:6`. This reports in-sample separation by prefix and the first prefix with perfect separation, if any. It does not estimate cross-fit loading stability or verify prefix invariance across distinct fits; that comparison would require separate `H = 3`, `4`, `5`, and `6` fits.
