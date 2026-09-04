# = ========================================================================== =
# - Script: config.R
# - Desc: Local and PBS runtime profiles for the application.
# = ========================================================================== =

source("src/utils/config.R")

application_profile <- function(
    output,
    fdapde_cpp,
    fdapde_repository,
    fdapde_core_repository,
    cc,
    cxx,
    eigen_include,
    execution_strategy,
    compile_strategy,
    application_data,
    r_library = "") {
  repo <- normalizePath(".", mustWork = FALSE)
  temporary <- file.path(output, "tmp")
  list(
    PATH_REPO = repo,
    PATH_RESULTS = file.path(output, "results"),
    PATH_IMAGES = file.path(output, "images"),
    PATH_TEST_DATA = file.path(output, "data/tests"),
    PATH_TMP = temporary,
    PATH_QUEUE = file.path(temporary, "queue"),
    PATH_LOGS = file.path(repo, "logs"),
    PATH_TMP_DATA = file.path(temporary, "data"),
    PATH_TMP_RESULTS = file.path(temporary, "results"),
    PATH_BUILD = file.path(output, "build"),
    CC = Sys.getenv("CC", unset = cc),
    CXX = Sys.getenv("CXX", unset = cxx),
    PATH_FDAPDE_CPP = fdapde_cpp,
    PATH_FDAPDE_CORE = file.path(fdapde_cpp, "fdaPDE/core"),
    PATH_EIGEN_INCLUDE = Sys.getenv("PATH_EIGEN_INCLUDE", unset = eigen_include),
    FDAPDE_CPP_REPOSITORY = fdapde_repository,
    FDAPDE_CORE_REPOSITORY = fdapde_core_repository,
    FDAPDE_CPP_BRANCH = Sys.getenv("FDAPDE_CPP_BRANCH", unset = "develop_fPLS"),
    FDAPDE_CPP_COMMIT = Sys.getenv(
      "FDAPDE_CPP_COMMIT", unset = "ecbf23ef37571174c438ab68c3d21d7ecd5cf18f"
    ),
    FDAPDE_CORE_COMMIT = Sys.getenv(
      "FDAPDE_CORE_COMMIT", unset = "1b75249a7b49ccee72cb94207a9dc5daaa21848c"
    ),
    FDAPDE_CPP_MANAGED = Sys.getenv("FDAPDE_CPP_MANAGED", unset = "true"),
    TEST_EXECUTION_STRATEGY = execution_strategy,
    COMPILE_STRATEGY = compile_strategy,
    DEFAULT_CPUS = Sys.getenv("DEFAULT_CPUS", unset = "1"),
    DEFAULT_MEM = Sys.getenv("DEFAULT_MEM", unset = "16GB"),
    DEFAULT_TIME = Sys.getenv("DEFAULT_TIME", unset = "12:00:00"),
    MULTITHREAD_CPUS = Sys.getenv("MULTITHREAD_CPUS", unset = "12"),
    MULTITHREAD_MEM = Sys.getenv("MULTITHREAD_MEM", unset = "32GB"),
    MULTITHREAD_TIME = Sys.getenv("MULTITHREAD_TIME", unset = "12:00:00"),
    COMPILE_CPUS = Sys.getenv("COMPILE_CPUS", unset = "4"),
    COMPILE_MEM = Sys.getenv("COMPILE_MEM", unset = "16GB"),
    COMPILE_TIME = Sys.getenv("COMPILE_TIME", unset = "04:00:00"),
    DEFAULT_MAX_JOBS = Sys.getenv("PBS_MAX_JOBS", unset = "15"),
    R_CRAN_REPO = "https://cloud.r-project.org",
    R_LIBS_USER = Sys.getenv("R_LIBS_USER", unset = r_library),
    R_LIBS_SITE = Sys.getenv("R_LIBS_SITE", unset = ""),
    PATH_APPLICATION_DATA = Sys.getenv("PATH_APPLICATION_DATA", unset = application_data)
  )
}

local_repo <- normalizePath(".", mustWork = FALSE)
local_output <- Sys.getenv("TESTBENCH_OUTPUT", unset = local_repo)
local_fdapde_repository <- Sys.getenv(
  "FDAPDE_CPP_REPOSITORY",
  unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp"
)

TESTBENCH_CONFIG_PROFILES <- list(
  macbook = application_profile(
    output = local_output,
    fdapde_cpp = Sys.getenv(
      "PATH_FDAPDE_CPP", unset = file.path(local_repo, "libraries", "fdaPDE-cpp")
    ),
    fdapde_repository = local_fdapde_repository,
    fdapde_core_repository = Sys.getenv(
      "FDAPDE_CORE_REPOSITORY", unset = file.path(local_fdapde_repository, "fdaPDE", "core")
    ),
    cc = "/opt/homebrew/bin/gcc-15",
    cxx = "/opt/homebrew/bin/g++-15",
    eigen_include = "/opt/homebrew/opt/eigen/include/eigen3",
    execution_strategy = "parallel",
    compile_strategy = "local",
    application_data = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain"
  ),
  `hpc-torque` = local({
    repo <- normalizePath(".", mustWork = FALSE)
    output <- Sys.getenv("TESTBENCH_OUTPUT", unset = repo)
    fdapde <- Sys.getenv("PATH_FDAPDE_CPP", unset = file.path(repo, "libraries", "fdaPDE-cpp"))
    application_profile(
      output = output,
      fdapde_cpp = fdapde,
      fdapde_repository = Sys.getenv(
        "FDAPDE_CPP_REPOSITORY", unset = "https://github.com/fdaPDE/fdaPDE-cpp.git"
      ),
      fdapde_core_repository = Sys.getenv(
        "FDAPDE_CORE_REPOSITORY", unset = "https://github.com/fdaPDE/fdaPDE-core.git"
      ),
      cc = "gcc",
      cxx = "g++",
      eigen_include = "/usr/include/eigen3",
      execution_strategy = "pbs",
      compile_strategy = "pbs",
      application_data = file.path(repo, "data", "brain"),
      r_library = file.path(repo, "libraries", "R")
    )
  })
)

if (config_is_cli("config.R")) config_main()
