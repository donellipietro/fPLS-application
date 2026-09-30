# = ========================================================================== =
# - Script: config.R
# - Desc: Editable local, container and cluster runtime profiles for the application.
# = ========================================================================== =

# Make reads these profiles before installing packages, so configuration uses only base R.
source("src/utils/config.R")

# Shared application paths, native revisions and resource defaults ----
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
    # keep generated artifacts under the selected output root
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
    # select the compiler, Eigen headers and pinned native stack
    CC = Sys.getenv("CC", unset = cc),
    CXX = Sys.getenv("CXX", unset = cxx),
    PATH_FDAPDE_CPP = fdapde_cpp,
    PATH_FDAPDE_CORE = file.path(fdapde_cpp, "fdaPDE/core"),
    PATH_EIGEN_INCLUDE = Sys.getenv("PATH_EIGEN_INCLUDE", unset = eigen_include),
    FDAPDE_CPP_REPOSITORY = fdapde_repository,
    FDAPDE_CORE_REPOSITORY = fdapde_core_repository,
    FDAPDE_CPP_BRANCH = Sys.getenv("FDAPDE_CPP_BRANCH", unset = "develop_fPLS"),
    FDAPDE_CPP_COMMIT = Sys.getenv(
      "FDAPDE_CPP_COMMIT", unset = "d32e45361200b16deb03ebdfad5ee55a703ff73a"
    ),
    FDAPDE_CORE_COMMIT = Sys.getenv(
      "FDAPDE_CORE_COMMIT", unset = "472f9bd374a63fbf851106e5c45f8870e31e8189"
    ),
    FDAPDE_CPP_MANAGED = Sys.getenv("FDAPDE_CPP_MANAGED", unset = "true"),
    # choose host execution by default; container profiles override these image settings
    SINGULARITY_IMAGE = "",
    SINGULARITY_IMAGE_SOURCE = "",
    SINGULARITY_BIND_PATHS = repo,
    DOCKER_IMAGE = "",
    DOCKER_BIND_PATHS = "",
    TEST_EXECUTION_STRATEGY = execution_strategy,
    COMPILE_STRATEGY = compile_strategy,
    # one computational thread per fit, with separate budgets for compilation and workers
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
    # locate host R libraries and the private preprocessed brain inputs
    R_CRAN_REPO = "https://cloud.r-project.org",
    R_LIBS_USER = Sys.getenv("R_LIBS_USER", unset = r_library),
    R_LIBS_SITE = Sys.getenv("R_LIBS_SITE", unset = ""),
    PATH_APPLICATION_DATA = Sys.getenv("PATH_APPLICATION_DATA", unset = application_data)
  )
}

# Profiles ----
local_repo <- normalizePath(".", mustWork = FALSE)
local_output <- Sys.getenv("TESTBENCH_OUTPUT", unset = local_repo)
local_fdapde_repository <- Sys.getenv(
  "FDAPDE_CPP_REPOSITORY",
  unset = "https://github.com/fdaPDE/fdaPDE-cpp.git"
)

TESTBENCH_CONFIG_PROFILES <- list(
  # macOS: Homebrew compiler and independent local workers
  macos = application_profile(
    output = local_output,
    fdapde_cpp = Sys.getenv(
      "PATH_FDAPDE_CPP", unset = file.path(local_repo, "libraries", "fdaPDE-cpp")
    ),
    fdapde_repository = local_fdapde_repository,
    fdapde_core_repository = Sys.getenv(
      "FDAPDE_CORE_REPOSITORY", unset = ""
    ),
    cc = "/opt/homebrew/bin/gcc-15",
    cxx = "/opt/homebrew/bin/g++-15",
    eigen_include = "/opt/homebrew/opt/eigen/include/eigen3",
    execution_strategy = "parallel",
    compile_strategy = "local",
    application_data = file.path(local_repo, "data", "brain")
  ),
  # Torque/PBS: native compilation and application fits on cluster nodes
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
        "FDAPDE_CORE_REPOSITORY", unset = ""
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

# Linux: use the same local workflow with system compiler and Eigen paths.
TESTBENCH_CONFIG_PROFILES$linux <- modifyList(
  TESTBENCH_CONFIG_PROFILES$macos,
  list(
    CC = Sys.getenv("CC", unset = "gcc"),
    CXX = Sys.getenv("CXX", unset = "g++"),
    PATH_EIGEN_INCLUDE = Sys.getenv("PATH_EIGEN_INCLUDE", unset = "/usr/include/eigen3")
  )
)

# Windows/WSL2: host R prepares data; Docker compiles and runs the native driver.
TESTBENCH_CONFIG_PROFILES$windows <- modifyList(
  TESTBENCH_CONFIG_PROFILES$linux,
  list(
    DOCKER_IMAGE = Sys.getenv("DOCKER_IMAGE", unset = "aldoclemente/fdapde-docker:latest"),
    DOCKER_BIND_PATHS = paste(unique(c(
      local_repo, local_output, TESTBENCH_CONFIG_PROFILES$linux$PATH_FDAPDE_CPP,
      TESTBENCH_CONFIG_PROFILES$linux$PATH_APPLICATION_DATA
    )), collapse = ","),
    R_LIBS_USER = Sys.getenv("R_LIBS_USER", unset = file.path(local_repo, "libraries", "R"))
  )
)

# Slurm: host R submits array jobs; Apptainer/Singularity provides the native runtime.
TESTBENCH_CONFIG_PROFILES$`hpc-slurm` <- modifyList(
  TESTBENCH_CONFIG_PROFILES$`hpc-torque`,
  list(
    TEST_EXECUTION_STRATEGY = "slurm",
    COMPILE_STRATEGY = "slurm",
    SINGULARITY_IMAGE = Sys.getenv(
      "SINGULARITY_IMAGE", unset = file.path(local_repo, "libraries", "fdapde-docker-latest.sif")
    ),
    SINGULARITY_IMAGE_SOURCE = Sys.getenv(
      "SINGULARITY_IMAGE_SOURCE", unset = "docker://aldoclemente/fdapde-docker:latest"
    ),
    SINGULARITY_BIND_PATHS = paste(unique(c(
      local_repo, local_output, TESTBENCH_CONFIG_PROFILES$`hpc-torque`$PATH_FDAPDE_CPP,
      TESTBENCH_CONFIG_PROFILES$`hpc-torque`$PATH_APPLICATION_DATA
    )), collapse = ",")
  )
)

# Command line entry point ----
if (config_is_cli("config.R")) config_main()
