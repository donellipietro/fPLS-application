# = ========================================================================== =
# - Test: fPLS brain application
# - Desc: Local neuroimaging application smoke and H-stability runs.
# = ========================================================================== =

TEST_SUITE <- "fPLS brain application"
test_suite <- "brain"

test_groups <- list(all = c(
  "smoke_overall_mean", "h_stability", "slider_resampling", "out_of_sample"
))

FORCE_FIT <- FALSE
FORCE_EVALUATE <- FALSE
RUN <- list(tests = TRUE, analysis = TRUE, quantitative_analysis = TRUE)

SMOKE_TEST <- tolower(Sys.getenv("SMOKE_TEST", "false")) %in% c("1", "true", "yes", "y")
IGNORE_CPP_OUTPUT <- TRUE

name_main_test_default <- "smoke_overall_mean"
