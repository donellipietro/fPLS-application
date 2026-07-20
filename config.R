# = ========================================================================== =
# - Script: config.R
# - Desc: Editable runtime profiles for this repository.
# = ========================================================================== =

# Make evaluates configuration before install, so this entry point stays base R only.
source("src/utils/config.R")


# Profiles ----

TESTBENCH_CONFIG_PROFILES <- list(
  macbook = local({
    PATH_REPO <- normalizePath(".", mustWork = FALSE)
    PATH_OUTPUT <- Sys.getenv("TESTBENCH_OUTPUT", unset = PATH_REPO)
    PATH_TMP <- file.path(PATH_OUTPUT, "tmp")
    PATH_FDAPDE_CPP <- Sys.getenv(
      "PATH_FDAPDE_CPP",
      unset = file.path(PATH_REPO, "libraries", "fdaPDE-cpp")
    )
	    FDAPDE_CPP_REPOSITORY <- Sys.getenv(
	      "FDAPDE_CPP_REPOSITORY",
	      unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp"
	    )

    list(
      PATH_REPO = PATH_REPO,

      PATH_RESULTS = file.path(PATH_OUTPUT, "results"),
      PATH_IMAGES = file.path(PATH_OUTPUT, "images"),
      PATH_TEST_DATA = file.path(PATH_OUTPUT, "data/tests"),
      PATH_TMP = PATH_TMP,
      PATH_QUEUE = file.path(PATH_TMP, "queue"),
      PATH_LOGS = file.path(PATH_REPO, "logs"),
      PATH_TMP_DATA = file.path(PATH_TMP, "data"),
      PATH_TMP_RESULTS = file.path(PATH_TMP, "results"),
      PATH_BUILD = file.path(PATH_OUTPUT, "build"),

      CC = Sys.getenv("CC", unset = "/opt/homebrew/bin/gcc-15"),
      CXX = Sys.getenv("CXX", unset = "/opt/homebrew/bin/g++-15"),
      PATH_FDAPDE_CPP = PATH_FDAPDE_CPP,
      PATH_FDAPDE_CORE = if (nzchar(PATH_FDAPDE_CPP)) {
        file.path(PATH_FDAPDE_CPP, "fdaPDE/core")
      } else {
        ""
      },
      PATH_EIGEN_INCLUDE = Sys.getenv(
        "PATH_EIGEN_INCLUDE",
        unset = "/opt/homebrew/opt/eigen/include/eigen3"
      ),
      FDAPDE_CPP_REPOSITORY = FDAPDE_CPP_REPOSITORY,
	      # Outer branch selected by this profile for the local fPLS stack
	      FDAPDE_CPP_BRANCH = Sys.getenv("FDAPDE_CPP_BRANCH", unset = "develop_fPLS"),
      # Set false to use PATH_FDAPDE_CPP without modifying its Git checkout
      FDAPDE_CPP_MANAGED = Sys.getenv("FDAPDE_CPP_MANAGED", unset = "true"),

      SINGULARITY_IMAGE = "",
      SINGULARITY_BIND_PATHS = PATH_REPO,
      DOCKER_IMAGE = "",
      DOCKER_BIND_PATHS = "",
      TEST_EXECUTION_STRATEGY = "parallel",
      COMPILE_STRATEGY = "local",
      MULTITHREAD_CPUS = Sys.getenv("MULTITHREAD_CPUS", unset = "12"),
      MULTITHREAD_MEM = Sys.getenv("MULTITHREAD_MEM", unset = "32GB"),
      MULTITHREAD_TIME = Sys.getenv("MULTITHREAD_TIME", unset = "12:00:00"),
	      R_CRAN_REPO = "https://cloud.r-project.org",
	      R_LIBS_USER = Sys.getenv("R_LIBS_USER", unset = ""),
	      R_LIBS_SITE = Sys.getenv("R_LIBS_SITE", unset = ""),
	      PATH_APPLICATION_DATA = Sys.getenv(
	        "PATH_APPLICATION_DATA",
	        unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain"
	      )
    )
  }),
  windows = local({
    PATH_REPO <- normalizePath(".", mustWork = FALSE)
    PATH_OUTPUT <- Sys.getenv("TESTBENCH_OUTPUT", unset = PATH_REPO)
    PATH_TMP <- file.path(PATH_OUTPUT, "tmp")
    PATH_FDAPDE_CPP <- Sys.getenv(
      "PATH_FDAPDE_CPP",
      unset = file.path(PATH_REPO, "libraries", "fdaPDE-cpp")
    )
	    FDAPDE_CPP_REPOSITORY <- Sys.getenv(
	      "FDAPDE_CPP_REPOSITORY",
	      unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp"
	    )
    DOCKER_BIND_PATHS <- unique(c(PATH_REPO, PATH_OUTPUT, PATH_FDAPDE_CPP))
    DOCKER_BIND_PATHS <- DOCKER_BIND_PATHS[nzchar(DOCKER_BIND_PATHS)]

    list(
      PATH_REPO = PATH_REPO,

      PATH_RESULTS = file.path(PATH_OUTPUT, "results"),
      PATH_IMAGES = file.path(PATH_OUTPUT, "images"),
      PATH_TEST_DATA = file.path(PATH_OUTPUT, "data/tests"),
      PATH_TMP = PATH_TMP,
      PATH_QUEUE = file.path(PATH_TMP, "queue"),
      PATH_LOGS = file.path(PATH_REPO, "logs"),
      PATH_TMP_DATA = file.path(PATH_TMP, "data"),
      PATH_TMP_RESULTS = file.path(PATH_TMP, "results"),
      PATH_BUILD = file.path(PATH_OUTPUT, "build"),

      CC = "gcc",
      CXX = "g++",
      PATH_FDAPDE_CPP = PATH_FDAPDE_CPP,
      PATH_FDAPDE_CORE = file.path(PATH_FDAPDE_CPP, "fdaPDE/core"),
      PATH_EIGEN_INCLUDE = "/usr/include/eigen3",
      FDAPDE_CPP_REPOSITORY = FDAPDE_CPP_REPOSITORY,
	      # Outer branch selected by this profile for the local fPLS stack
	      FDAPDE_CPP_BRANCH = Sys.getenv("FDAPDE_CPP_BRANCH", unset = "develop_fPLS"),
      # Set false to use PATH_FDAPDE_CPP without modifying its Git checkout
      FDAPDE_CPP_MANAGED = Sys.getenv("FDAPDE_CPP_MANAGED", unset = "true"),

      SINGULARITY_IMAGE = "",
      SINGULARITY_BIND_PATHS = PATH_REPO,
      DOCKER_IMAGE = Sys.getenv(
        "DOCKER_IMAGE",
        unset = "aldoclemente/fdapde-docker:latest"
      ),
      DOCKER_BIND_PATHS = paste(DOCKER_BIND_PATHS, collapse = ","),
      TEST_EXECUTION_STRATEGY = "parallel",
      COMPILE_STRATEGY = "local",
      MULTITHREAD_CPUS = Sys.getenv("MULTITHREAD_CPUS", unset = "12"),
      MULTITHREAD_MEM = Sys.getenv("MULTITHREAD_MEM", unset = "8GB"),
      MULTITHREAD_TIME = Sys.getenv("MULTITHREAD_TIME", unset = "12:00:00"),
      R_CRAN_REPO = "https://cloud.r-project.org",
	      R_LIBS_USER = Sys.getenv(
	        "R_LIBS_USER",
	        unset = file.path(PATH_REPO, "libraries", "R")
	      ),
	      R_LIBS_SITE = Sys.getenv("R_LIBS_SITE", unset = ""),
	      PATH_APPLICATION_DATA = Sys.getenv(
	        "PATH_APPLICATION_DATA",
	        unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain"
	      )
    )
  }),
  `hpc-slurm` = local({
    PATH_REPO <- normalizePath(".", mustWork = FALSE)
    PATH_OUTPUT <- Sys.getenv("TESTBENCH_OUTPUT", unset = PATH_REPO)
    PATH_TMP <- file.path(PATH_OUTPUT, "tmp")
    PATH_FDAPDE_CPP <- Sys.getenv(
      "PATH_FDAPDE_CPP",
      unset = file.path(PATH_REPO, "libraries", "fdaPDE-cpp")
    )
	    FDAPDE_CPP_REPOSITORY <- Sys.getenv(
	      "FDAPDE_CPP_REPOSITORY",
	      unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-simulation-study/libraries/fdaPDE-cpp"
	    )
    SINGULARITY_IMAGE <- Sys.getenv(
      "SINGULARITY_IMAGE",
      unset = file.path(PATH_REPO, "libraries", "fdapde-docker-latest.sif")
    )
    SINGULARITY_BIND_PATHS <- unique(c(PATH_REPO, PATH_OUTPUT, PATH_FDAPDE_CPP))
    SINGULARITY_BIND_PATHS <- SINGULARITY_BIND_PATHS[nzchar(SINGULARITY_BIND_PATHS)]

    list(
      PATH_REPO = PATH_REPO,

      PATH_RESULTS = file.path(PATH_OUTPUT, "results"),
      PATH_IMAGES = file.path(PATH_OUTPUT, "images"),
      PATH_TEST_DATA = file.path(PATH_OUTPUT, "data/tests"),
      PATH_TMP = PATH_TMP,
      PATH_QUEUE = file.path(PATH_TMP, "queue"),
      PATH_LOGS = file.path(PATH_REPO, "logs"),
      PATH_TMP_DATA = file.path(PATH_TMP, "data"),
      PATH_TMP_RESULTS = file.path(PATH_TMP, "results"),
      PATH_BUILD = file.path(PATH_OUTPUT, "build"),

      CC = Sys.getenv("CC", unset = "gcc"),
      CXX = Sys.getenv("CXX", unset = "g++"),
      PATH_FDAPDE_CPP = PATH_FDAPDE_CPP,
      PATH_FDAPDE_CORE = if (nzchar(PATH_FDAPDE_CPP)) {
        file.path(PATH_FDAPDE_CPP, "fdaPDE/core")
      } else {
        ""
      },
      PATH_EIGEN_INCLUDE = Sys.getenv(
        "PATH_EIGEN_INCLUDE",
        unset = "/usr/include/eigen3"
      ),
      FDAPDE_CPP_REPOSITORY = FDAPDE_CPP_REPOSITORY,
	      # Outer branch selected by this profile for the local fPLS stack
	      FDAPDE_CPP_BRANCH = Sys.getenv("FDAPDE_CPP_BRANCH", unset = "develop_fPLS"),
      # Set false to use PATH_FDAPDE_CPP without modifying its Git checkout
      FDAPDE_CPP_MANAGED = Sys.getenv("FDAPDE_CPP_MANAGED", unset = "true"),

      SINGULARITY_IMAGE = SINGULARITY_IMAGE,
      SINGULARITY_IMAGE_SOURCE = Sys.getenv(
        "SINGULARITY_IMAGE_SOURCE",
        unset = "docker://aldoclemente/fdapde-docker:latest"
      ),
      SINGULARITY_BIND_PATHS = paste(SINGULARITY_BIND_PATHS, collapse = ","),
      DOCKER_IMAGE = "",
      DOCKER_BIND_PATHS = "",
      TEST_EXECUTION_STRATEGY = "slurm",
      COMPILE_STRATEGY = "slurm",
      DEFAULT_CPUS = Sys.getenv("DEFAULT_CPUS", unset = "1"),
      DEFAULT_MEM = Sys.getenv("DEFAULT_MEM", unset = "8GB"),
      DEFAULT_TIME = Sys.getenv("DEFAULT_TIME", unset = "04:00:00"),
      MULTITHREAD_CPUS = Sys.getenv("MULTITHREAD_CPUS", unset = "20"),
      MULTITHREAD_MEM = Sys.getenv("MULTITHREAD_MEM", unset = "32GB"),
      MULTITHREAD_TIME = Sys.getenv("MULTITHREAD_TIME", unset = "12:00:00"),
      R_CRAN_REPO = "https://cloud.r-project.org",
	      R_LIBS_USER = Sys.getenv(
	        "R_LIBS_USER",
	        unset = file.path(PATH_REPO, "libraries", "R")
	      ),
	      R_LIBS_SITE = Sys.getenv("R_LIBS_SITE", unset = ""),
	      PATH_APPLICATION_DATA = Sys.getenv(
	        "PATH_APPLICATION_DATA",
	        unset = "/Users/pietrodonelli/Documents/University/projects/fPLS/fPLS-regression/data/brain"
	      )
    )
  })
)


# Command line entry point ----

if (config_is_cli("config.R")) {
  config_main()
}
