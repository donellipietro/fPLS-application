SHELL := /bin/bash
RSCRIPT ?= Rscript
PVPYTHON ?= pvpython

ACTIVE_ENV_PROFILE := $(strip $(shell if [ -f .env ]; then set -a; . ./.env >/dev/null 2>&1; printf '%s' "$$TESTBENCH_PROFILE"; fi))
REQUESTED_PROFILE := $(strip $(PROFILE))
TESTBENCH_PROFILE ?= $(if $(ACTIVE_ENV_PROFILE),$(ACTIVE_ENV_PROFILE),macos)
ifneq ($(REQUESTED_PROFILE),)
override TESTBENCH_PROFILE := $(REQUESTED_PROFILE)
endif

SMOKE_TEST ?= 0
COMPILE_JOBS ?=
COMPILE_TARGET ?= $(if $(TARGET),$(TARGET),$(if $(EXEC),$(EXEC),$(SOURCE)))
SLURM_ARRAY_LIMIT ?=
SLURM_COMPILE ?= 0
SLURM_AGGREGATE ?= 1
SLURM_DRY_RUN ?= 0
SLURM_CPUS ?=
SLURM_MEM ?=
SLURM_TIME ?=
SLURM_MULTI_CPUS ?=
SLURM_MULTI_MEM ?=
SLURM_MULTI_TIME ?=
SLURM_PARTITION ?=
SLURM_ACCOUNT ?=
SLURM_QOS ?=
SLURM_AGG_CPUS ?=
SLURM_AGG_MEM ?=
SLURM_AGG_TIME ?=
SLURM_COMPILE_CPUS ?=
SLURM_COMPILE_MEM ?=
SLURM_COMPILE_TIME ?=
SLURM_COMPILE_JOBS ?=
SLURM_COMPILE_MODEL ?=
SLURM_COMPILE_TARGET ?=
PBS_DRY_RUN ?= 0
PBS_CPUS ?=
PBS_MEM ?=
PBS_TIME ?=
PBS_MULTI_CPUS ?=
PBS_MULTI_MEM ?=
PBS_MULTI_TIME ?=
PBS_MAX_JOBS ?=
PBS_QUEUE ?=
PBS_ACCOUNT ?=
PBS_AGGREGATE ?= 1
PBS_COMPILE_CPUS ?=
PBS_COMPILE_MEM ?=
PBS_COMPILE_TIME ?=
PBS_COMPILE_JOBS ?=
PBS_COMPILE_DRY_RUN ?= 0

define config_value
$(strip $(shell $(RSCRIPT) -e 'source("config.R"); profile <- "$(TESTBENCH_PROFILE)"; if (!profile %in% available_profiles()) quit(status = 0); cfg <- get_config(profile); value <- cfg[["$(1)"]]; if (is.null(value)) value <- ""; cat(value)'))
endef

PATH_REPO := $(call config_value,PATH_REPO)
PATH_CPP := $(call config_value,PATH_CPP)
PATH_RESULTS := $(call config_value,PATH_RESULTS)
PATH_IMAGES := $(call config_value,PATH_IMAGES)
PATH_TEST_DATA := $(call config_value,PATH_TEST_DATA)
PATH_TMP := $(call config_value,PATH_TMP)
PATH_LOGS := $(call config_value,PATH_LOGS)
PATH_BUILD := $(call config_value,PATH_BUILD)
PATH_FDAPDE_CPP := $(call config_value,PATH_FDAPDE_CPP)
FDAPDE_CPP_REPOSITORY := $(call config_value,FDAPDE_CPP_REPOSITORY)
FDAPDE_CORE_REPOSITORY := $(call config_value,FDAPDE_CORE_REPOSITORY)
FDAPDE_CPP_BRANCH := $(call config_value,FDAPDE_CPP_BRANCH)
FDAPDE_CPP_COMMIT := $(call config_value,FDAPDE_CPP_COMMIT)
FDAPDE_CORE_COMMIT := $(call config_value,FDAPDE_CORE_COMMIT)
FDAPDE_CPP_MANAGED := $(call config_value,FDAPDE_CPP_MANAGED)
SINGULARITY_IMAGE := $(call config_value,SINGULARITY_IMAGE)
SINGULARITY_IMAGE_SOURCE := $(call config_value,SINGULARITY_IMAGE_SOURCE)
DOCKER_IMAGE := $(call config_value,DOCKER_IMAGE)
TEST_EXECUTION_STRATEGY := $(call config_value,TEST_EXECUTION_STRATEGY)
COMPILE_STRATEGY := $(call config_value,COMPILE_STRATEGY)

.PHONY: all help config write_env create_dirs install install_femR build ensure_env \
        compile compile_all run_test application_figure_panels \
        clean_tmp clean_compiled clean clean_test distclean

all: build

## Regenerate the two application figure panels used by the Affinity layout.
application_figure_panels:
	@$(RSCRIPT) paper-figures/scripts/A_latent_scores.R
	@PVPYTHON="$(PVPYTHON)" $(RSCRIPT) paper-figures/scripts/A_slider.R

## Print one runtime profile.
config:
	@if [ -z "$(REQUESTED_PROFILE)" ]; then \
		echo "Usage: make config PROFILE=<profile>"; \
		$(RSCRIPT) -e 'source("config.R"); cat(paste0("  - ", available_profiles(), collapse = "\n"), "\n", sep = "")'; \
	else \
		$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --print; \
	fi

write_env:
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --write-env

create_dirs:
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --create-dirs

ensure_env:
	@if [ ! -f .env ]; then echo "Error: .env not found. Run: make build PROFILE=<profile>"; exit 1; fi

install_femR: write_env create_dirs
	@set -a; source .env; set +a; $(RSCRIPT) src/installation/install_femR.R

install: install_femR

## Configure paths, install R dependencies, and prepare C++ libraries.
build:
	@if [ -z "$(REQUESTED_PROFILE)" ]; then \
		echo "Usage: make build PROFILE=<profile>"; \
		$(RSCRIPT) -e 'source("config.R"); cat(paste0("  - ", available_profiles(), collapse = "\n"), "\n", sep = "")'; \
	else \
		$(MAKE) --no-print-directory config PROFILE="$(TESTBENCH_PROFILE)" && \
		if [ -n "$(SINGULARITY_IMAGE)" ]; then \
			./cpp/prepare_image.sh "$(SINGULARITY_IMAGE_SOURCE)" "$(SINGULARITY_IMAGE)"; \
		fi && \
		if [ -n "$(DOCKER_IMAGE)" ]; then \
			./cpp/prepare_docker_image.sh "$(DOCKER_IMAGE)"; \
		fi && \
		$(MAKE) --no-print-directory install PROFILE="$(TESTBENCH_PROFILE)" && \
		./cpp/prepare_json.sh && \
		FDAPDE_CPP_MANAGED="$(FDAPDE_CPP_MANAGED)" \
		FDAPDE_CPP_COMMIT="$(FDAPDE_CPP_COMMIT)" \
		FDAPDE_CORE_COMMIT="$(FDAPDE_CORE_COMMIT)" \
		FDAPDE_CORE_REPOSITORY="$(FDAPDE_CORE_REPOSITORY)" \
			./cpp/clone_fdapde.sh "$(FDAPDE_CPP_REPOSITORY)" "$(FDAPDE_CPP_BRANCH)" "$(PATH_FDAPDE_CPP)"; \
	fi

## Compile every C++ model using the selected local, Slurm or PBS profile.
compile_all: ensure_env
	@if [ "$(COMPILE_STRATEGY)" = "slurm" ]; then \
		SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
		SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
		SLURM_DRY_RUN="$(SLURM_DRY_RUN)" SLURM_PARTITION="$(SLURM_PARTITION)" \
		SLURM_ACCOUNT="$(SLURM_ACCOUNT)" SLURM_QOS="$(SLURM_QOS)" ./cpp/compile_slurm.sh --all; \
	elif [ "$(COMPILE_STRATEGY)" = "pbs" ]; then \
		PBS_COMPILE_CPUS="$(PBS_COMPILE_CPUS)" PBS_COMPILE_MEM="$(PBS_COMPILE_MEM)" \
		PBS_COMPILE_TIME="$(PBS_COMPILE_TIME)" PBS_COMPILE_JOBS="$(PBS_COMPILE_JOBS)" \
		PBS_COMPILE_DRY_RUN="$(PBS_COMPILE_DRY_RUN)" PBS_QUEUE="$(PBS_QUEUE)" \
		PBS_ACCOUNT="$(PBS_ACCOUNT)" ./cpp/compile_pbs.sh --all; \
	else \
		COMPILE_JOBS="$(COMPILE_JOBS)" ./cpp/compile.sh --all; \
	fi

## Compile one model, optionally selecting TARGET.
compile: ensure_env
	@set -euo pipefail; \
	if [ -z "$(MODEL)" ]; then ./cpp/compile.sh --make-help; else \
		args=("$(MODEL)"); \
		if [ -n "$(COMPILE_TARGET)" ]; then args+=("$(COMPILE_TARGET)"); fi; \
		if [ "$(COMPILE_STRATEGY)" = "slurm" ]; then \
			SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
			SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
			SLURM_DRY_RUN="$(SLURM_DRY_RUN)" SLURM_PARTITION="$(SLURM_PARTITION)" \
			SLURM_ACCOUNT="$(SLURM_ACCOUNT)" SLURM_QOS="$(SLURM_QOS)" ./cpp/compile_slurm.sh "$${args[@]}"; \
		elif [ "$(COMPILE_STRATEGY)" = "pbs" ]; then \
			PBS_COMPILE_CPUS="$(PBS_COMPILE_CPUS)" PBS_COMPILE_MEM="$(PBS_COMPILE_MEM)" \
			PBS_COMPILE_TIME="$(PBS_COMPILE_TIME)" PBS_COMPILE_JOBS="$(PBS_COMPILE_JOBS)" \
			PBS_COMPILE_DRY_RUN="$(PBS_COMPILE_DRY_RUN)" PBS_QUEUE="$(PBS_QUEUE)" \
			PBS_ACCOUNT="$(PBS_ACCOUNT)" ./cpp/compile_pbs.sh "$${args[@]}"; \
		else COMPILE_JOBS="$(COMPILE_JOBS)" ./cpp/compile.sh "$${args[@]}"; fi; \
	fi

ifneq ($(strip $(TEST_SUITE)),)
run_test: MODEL := $(TEST_SUITE)
run_test: compile
endif
## Run one analysis or the all group using the selected execution profile.
run_test: ensure_env
	@if [ -z "$(TEST_SUITE)" ] || [ -z "$(TEST_NAME)" ]; then \
		echo "Usage: make run_test TEST_SUITE=brain TEST_NAME=<target>"; \
	else \
		case "$(TEST_EXECUTION_STRATEGY)" in \
			serial) runner=./tests/run_tests.sh ;; \
			parallel) runner=./tests/run_tests_parallel.sh ;; \
			slurm) runner=./tests/run_tests_slurm.sh ;; \
			pbs) runner=./tests/run_tests_pbs.sh ;; \
			*) echo "Unknown TEST_EXECUTION_STRATEGY: $(TEST_EXECUTION_STRATEGY). Use serial, parallel, slurm, or pbs."; exit 1 ;; \
		esac; \
		SLURM_ARRAY_LIMIT="$(SLURM_ARRAY_LIMIT)" SLURM_COMPILE="$(SLURM_COMPILE)" \
		SLURM_AGGREGATE="$(SLURM_AGGREGATE)" SLURM_DRY_RUN="$(SLURM_DRY_RUN)" \
		SLURM_CPUS="$(SLURM_CPUS)" SLURM_MEM="$(SLURM_MEM)" SLURM_TIME="$(SLURM_TIME)" \
		SLURM_MULTI_CPUS="$(SLURM_MULTI_CPUS)" SLURM_MULTI_MEM="$(SLURM_MULTI_MEM)" SLURM_MULTI_TIME="$(SLURM_MULTI_TIME)" \
		SLURM_PARTITION="$(SLURM_PARTITION)" SLURM_ACCOUNT="$(SLURM_ACCOUNT)" SLURM_QOS="$(SLURM_QOS)" \
		SLURM_AGG_CPUS="$(SLURM_AGG_CPUS)" SLURM_AGG_MEM="$(SLURM_AGG_MEM)" SLURM_AGG_TIME="$(SLURM_AGG_TIME)" \
		SLURM_COMPILE_MODEL="$(SLURM_COMPILE_MODEL)" SLURM_COMPILE_TARGET="$(SLURM_COMPILE_TARGET)" \
		SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
		SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
		PBS_DRY_RUN="$(PBS_DRY_RUN)" PBS_CPUS="$(PBS_CPUS)" PBS_MEM="$(PBS_MEM)" \
		PBS_TIME="$(PBS_TIME)" PBS_MULTI_CPUS="$(PBS_MULTI_CPUS)" PBS_MULTI_MEM="$(PBS_MULTI_MEM)" \
		PBS_MULTI_TIME="$(PBS_MULTI_TIME)" PBS_MAX_JOBS="$(PBS_MAX_JOBS)" PBS_QUEUE="$(PBS_QUEUE)" \
		PBS_ACCOUNT="$(PBS_ACCOUNT)" PBS_AGGREGATE="$(PBS_AGGREGATE)" SMOKE_TEST="$(SMOKE_TEST)" \
			"$$runner" "$(TEST_SUITE)" "$(TEST_NAME)"; \
	fi

clean_tmp:
	@$(RM) -r "$(PATH_TMP)"
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --create-dirs

clean_compiled:
	@$(RM) -r "$(PATH_BUILD)"
	@find "$(PATH_CPP)" -mindepth 2 -maxdepth 2 -type f \( -name 'fit_model' -o -name 'fit_model_*' \) -exec $(RM) {} +

clean: clean_tmp
	@$(RM) -r "$(PATH_LOGS)"

clean_test:
	@if [ -z "$(TEST_SUITE)" ] || [ -z "$(TEST_NAME)" ]; then \
		echo "Usage: make clean_test TEST_SUITE=brain TEST_NAME=<target>"; \
	else \
		resolved_tests="$$( $(RSCRIPT) src/resolve_test_names.R "$(TEST_SUITE)" "$(TEST_NAME)" )" || exit 1; \
		for test_name in $$resolved_tests; do \
			$(RM) -r "$(PATH_RESULTS)/$(TEST_SUITE)/$$test_name"; \
			$(RM) -r "$(PATH_IMAGES)/$(TEST_SUITE)/$$test_name"; \
			$(RM) -r "$(PATH_RESULTS)/$(TEST_SUITE)/aggregate/$$test_name"; \
			$(RM) -r "$(PATH_IMAGES)/$(TEST_SUITE)/aggregate/$$test_name"; \
		done; \
		$(RM) -r "$(PATH_RESULTS)/$(TEST_SUITE)/aggregate/$(TEST_NAME)"; \
	fi

distclean: clean clean_compiled
	@echo "This removes all generated results, images, data, libraries, and .env."
	@read -p "Continue? [y/n]: " confirm && [ "$$confirm" = "y" ]
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --remove-links
	@$(RM) -r "$(PATH_IMAGES)" "$(PATH_RESULTS)" "$(PATH_TEST_DATA)" "$(PATH_TMP)" "$(PATH_REPO)/libraries"
	@$(RM) .env

## Show available targets.
help:
	@awk '/^##/ { description=substr($$0,4); next } /^[a-zA-Z0-9_.-]+:/ && description { target=$$1; sub(/:.*/,"",target); printf "%-28s %s\n", target, description; description="" }' $(MAKEFILE_LIST)
