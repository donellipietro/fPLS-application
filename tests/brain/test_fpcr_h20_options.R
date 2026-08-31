suppressMessages(library(jsonlite))
suppressMessages(library(glue))

source("src/utils/options.R")
source("src/utils/directories.R")
source("tests/brain/config.R")
source("tests/brain/utils/generate_options.R")

queue <- tempfile("fpcr_h20_options_")
generate_options("brain", "fpcr_h20_separation", queue)
files <- list.files(queue, pattern = "[.]json$", full.names = TRUE)
stopifnot(length(files) == 1L)

options <- fromJSON(files, simplifyVector = TRUE)
stopifnot(
  identical(options$name_test, "fpcr_h20_separation_H20"),
  identical(options$model_names, "fPCR"),
  identical(options$model$n_comp, 20L),
  identical(as.numeric(options$regularization$lambda_grid), 10^(-15:6)),
  identical(as.numeric(options$mean_estimation$lambda_grid), 10^(-15:2)),
  identical(options$provenance$validation_status, "complete_data_exploratory_diagnostic"),
  isTRUE(options$output$write_reconstructions),
  !isTRUE(options$output$write_beta)
)

cat("fPCR H20 option checks passed.\n")
