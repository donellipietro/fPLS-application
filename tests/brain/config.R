# = ========================================================================== =
# - Test: fPLS brain application
# - Desc: Complete-data, resampling, and fPCR analyses used in the manuscript.
# = ========================================================================== =

TEST_SUITE <- "fPLS brain application"
test_suite <- "brain"

test_groups <- list(all = c(
  "h_stability", "slider_resampling", "fpcr_h20_separation"
))

FORCE_FIT <- FALSE
FORCE_EVALUATE <- FALSE
RUN <- list(tests = TRUE, analysis = TRUE, quantitative_analysis = TRUE)

SMOKE_TEST <- tolower(Sys.getenv("SMOKE_TEST", "false")) %in% c("1", "true", "yes", "y")
IGNORE_CPP_OUTPUT <- TRUE

name_main_test_default <- "h_stability"
