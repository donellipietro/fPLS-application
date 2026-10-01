# = ========================================================================== =
# - Script: process.R
# - Desc: Runs native commands and records their status, elapsed time and peak RSS.
# = ========================================================================== =

# normalize /usr/bin/time output: macOS reports bytes, Linux reports KiB
parse_peak_rss_mib <- function(lines, sysname = Sys.info()[["sysname"]]) {
  line <- grep("maximum resident set size|Maximum resident set size", lines, value = TRUE)
  if (length(line) == 0L) return(NaN)
  value <- suppressWarnings(as.numeric(regmatches(line[1], regexpr("[0-9]+(\\.[0-9]+)?", line[1]))))
  if (length(value) == 0L || is.na(value)) return(NaN)
  if (identical(sysname, "Darwin")) value / 1024^2 else value / 1024
}

# preserve the command's exit status and remove the temporary measurement after reading it
system_with_memory <- function(command, ignore.stdout = FALSE) {
  started <- Sys.time()
  docker <- nzchar(Sys.getenv("DOCKER_IMAGE", unset = ""))
  time_file <- tempfile("time_", tmpdir = if (docker) {
    Sys.getenv("PATH_TMP", unset = tempdir())
  } else tempdir())
  on.exit(unlink(time_file), add = TRUE)

  if (docker) {
    # cpp/run.sh measures the model inside Docker and writes to the shared temporary directory
    # export in the command's shell so the heartbeat's compound command inherits the path
    command <- paste0("export TESTBENCH_MEMORY_FILE=", shQuote(time_file), "; ", command)
    status <- system(command, ignore.stdout = ignore.stdout)
  } else if (file.exists("/usr/bin/time")) {
    # the platform-specific flags record peak RSS for the command and its native children
    time_arg <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
    status <- system2(
      "/usr/bin/time",
      c(time_arg, "-o", shQuote(time_file), "sh", "-c", shQuote(command)),
      stdout = if (ignore.stdout) FALSE else "",
      stderr = ""
    )
  } else {
    # keep execution available when the host cannot provide a memory measurement
    status <- system(command, ignore.stdout = ignore.stdout)
  }

  peak_ram_mib <- if (file.exists(time_file)) {
    parse_peak_rss_mib(
      readLines(time_file, warn = FALSE),
      sysname = if (docker) "Linux" else Sys.info()[["sysname"]]
    )
  } else NaN
  list(execution_time = Sys.time() - started, peak_ram_mib = peak_ram_mib, status = status)
}
