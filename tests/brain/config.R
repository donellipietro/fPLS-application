# = ========================================================================== =
# - Test: fPLS brain application
# - Desc: Complete-data, resampling, and fPCR analyses used in the manuscript.
# = ========================================================================== =

## Test suite full name and directory name ----
TEST_SUITE <- "fPLS brain application"
test_suite <- "brain"

## Analyses included in the grouped all target ----
test_groups <- list(all = c(
  "h_stability", "slider_resampling", "fpcr_h20_separation"
))

## Fit and evaluation controls ----
FORCE_FIT <- FALSE
FORCE_EVALUATE <- FALSE
RUN <- list(tests = TRUE, analysis = TRUE, quantitative_analysis = TRUE)

## Execution modifiers ----
SMOKE_TEST <- tolower(Sys.getenv("SMOKE_TEST", "false")) %in% c("1", "true", "yes", "y")
IGNORE_CPP_OUTPUT <- TRUE

## Defaults ----
name_main_test_default <- "h_stability"
