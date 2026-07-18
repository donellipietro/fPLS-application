
# Define commands ----
SHELL := /bin/bash
RSCRIPT ?= Rscript

ACTIVE_ENV_PROFILE := $(strip $(shell if [ -f .env ]; then set -a; . ./.env >/dev/null 2>&1; printf '%s' "$$TESTBENCH_PROFILE"; fi))
REQUESTED_PROFILE := $(strip $(PROFILE))
TESTBENCH_PROFILE ?= $(if $(ACTIVE_ENV_PROFILE),$(ACTIVE_ENV_PROFILE),macbook)
ifneq ($(REQUESTED_PROFILE),)
override TESTBENCH_PROFILE := $(REQUESTED_PROFILE)
endif
SLURM_ARRAY_LIMIT ?=
SLURM_COMPILE ?= 0
SLURM_AGGREGATE ?= 1
SLURM_DRY_RUN ?= 0
SMOKE_TEST ?= 0
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
COMPILE_JOBS ?=
COMPILE_TARGET ?= $(if $(TARGET),$(TARGET),$(if $(EXEC),$(EXEC),$(SOURCE)))

define config_value
$(strip $(shell $(RSCRIPT) -e 'source("config.R"); profile <- "$(TESTBENCH_PROFILE)"; if (!profile %in% available_profiles()) quit(status = 0); cfg <- get_config(profile); value <- cfg[["$(1)"]]; if (is.null(value)) value <- ""; cat(value)'))
endef


# Repository paths ----
PATH_REPO := $(call config_value,PATH_REPO)
PATH_CPP := $(call config_value,PATH_CPP)
PATH_RESULTS := $(call config_value,PATH_RESULTS)
PATH_IMAGES := $(call config_value,PATH_IMAGES)
PATH_TEST_DATA := $(call config_value,PATH_TEST_DATA)
PATH_TMP := $(call config_value,PATH_TMP)
PATH_QUEUE := $(call config_value,PATH_QUEUE)
PATH_LOGS := $(call config_value,PATH_LOGS)
PATH_TMP_DATA := $(call config_value,PATH_TMP_DATA)
PATH_TMP_RESULTS := $(call config_value,PATH_TMP_RESULTS)
PATH_BUILD := $(call config_value,PATH_BUILD)
PATH_FDAPDE_CPP := $(call config_value,PATH_FDAPDE_CPP)
FDAPDE_CPP_REPOSITORY := $(call config_value,FDAPDE_CPP_REPOSITORY)
FDAPDE_CPP_BRANCH := $(call config_value,FDAPDE_CPP_BRANCH)
FDAPDE_CPP_MANAGED := $(call config_value,FDAPDE_CPP_MANAGED)
SINGULARITY_IMAGE := $(call config_value,SINGULARITY_IMAGE)
SINGULARITY_IMAGE_SOURCE := $(call config_value,SINGULARITY_IMAGE_SOURCE)
DOCKER_IMAGE := $(call config_value,DOCKER_IMAGE)
TEST_EXECUTION_STRATEGY := $(call config_value,TEST_EXECUTION_STRATEGY)
COMPILE_STRATEGY := $(call config_value,COMPILE_STRATEGY)


# Targets ----
.PHONY: help config write_env install install_femR build create_dirs \
        ensure_env \
        compile compile_all \
        clean_tmp clean_compiled clean_links clean clean_test distclean \
        run_test inspect_results


all: build


# Config targets ----
## Print the selected configuration profile
config:
	@if [ -z "$(REQUESTED_PROFILE)" ]; then \
		echo ""; \
		echo "make config requires an explicit PROFILE."; \
		echo ""; \
		echo "Usage:"; \
		echo "  make config PROFILE=<profile>"; \
		echo ""; \
		echo "Available profiles:"; \
		$(RSCRIPT) -e 'source("config.R"); cat(paste0("  - ", available_profiles(), collapse = "\n"), "\n", sep = "")'; \
		echo ""; \
	else \
		echo ""; \
		echo "Configuration profile: $(TESTBENCH_PROFILE)"; \
		echo ""; \
		$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --print; \
		echo ""; \
	fi

write_env:
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --write-env

ensure_env:
	@if [ ! -f .env ]; then \
		echo "Error: .env not found. Run: make build PROFILE=<profile>"; \
		exit 1; \
	fi


# Installation targets ----
install_femR: write_env create_dirs
	@printf '\nInstalling femR...\n'
	@set -a; source .env; set +a; $(RSCRIPT) src/installation/install_femR.R
# install_fdaPDE:
# 	@printf '\nInstalling fdaPDE...\n'
# 	@$(RSCRIPT) src/installation/install_fdaPDE.R
install: install_femR
	@printf '\nInstallation completed.\n'


# Build target ----
create_dirs:
	@echo "Creating necessary directories..."
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --create-dirs

## Write .env, create directories, install dependencies, and prepare C++ libraries
build:
	@if [ -z "$(REQUESTED_PROFILE)" ]; then \
		echo ""; \
		echo "make build requires an explicit PROFILE."; \
		echo ""; \
		echo "Usage:"; \
		echo "  make build PROFILE=<profile>"; \
		echo ""; \
		echo "Available profiles:"; \
		$(RSCRIPT) -e 'source("config.R"); cat(paste0("  - ", available_profiles(), collapse = "\n"), "\n", sep = "")'; \
		echo ""; \
	else \
		$(MAKE) --no-print-directory config PROFILE="$(TESTBENCH_PROFILE)" && \
		if [ -n "$(SINGULARITY_IMAGE)" ]; then \
			printf '\nInstalling container image...\n' && \
			./cpp/prepare_image.sh "$(SINGULARITY_IMAGE_SOURCE)" "$(SINGULARITY_IMAGE)" && \
			printf 'Installation completed.\n\n'; \
		fi && \
		if [ -n "$(DOCKER_IMAGE)" ]; then \
			printf '\nInstalling Docker image...\n' && \
			./cpp/prepare_docker_image.sh "$(DOCKER_IMAGE)" && \
			printf 'Installation completed.\n\n'; \
		fi && \
		$(MAKE) --no-print-directory install PROFILE="$(TESTBENCH_PROFILE)" && \
		printf '\nInstalling nlohmann/json...\n' && \
		./cpp/prepare_json.sh && \
		printf 'Installation completed.\n\n' && \
		printf '\nInstalling fdaPDE-cpp...\n' && \
		FDAPDE_CPP_MANAGED="$(FDAPDE_CPP_MANAGED)" \
			./cpp/clone_fdapde.sh "$(FDAPDE_CPP_REPOSITORY)" "$(FDAPDE_CPP_BRANCH)" "$(PATH_FDAPDE_CPP)" && \
		printf 'Installation completed.\n\n' && \
		printf 'Profile %s build completed.\n\n' "$(TESTBENCH_PROFILE)"; \
	fi

# Compile targets ----

## Compile all models under cpp/
compile_all: ensure_env
	@if [ "$(COMPILE_STRATEGY)" = "slurm" ]; then \
		SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" \
		SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
		SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" \
		SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
		SLURM_DRY_RUN="$(SLURM_DRY_RUN)" \
		SLURM_PARTITION="$(SLURM_PARTITION)" \
		SLURM_ACCOUNT="$(SLURM_ACCOUNT)" \
		SLURM_QOS="$(SLURM_QOS)" \
		./cpp/compile_slurm.sh --all; \
	else \
		COMPILE_JOBS="$(COMPILE_JOBS)" ./cpp/compile.sh --all; \
	fi

## Compile all mains found in cpp/$(MODEL), or one executable with TARGET
# Usage: make compile MODEL=my_model [TARGET=fit_model]
compile: ensure_env
	@set -euo pipefail; \
	if [ -z "$(MODEL)" ]; then \
		printf '\n'; \
		./cpp/compile.sh --make-help; \
		printf '\n'; \
	else \
		args=("$(MODEL)"); \
		if [ -n "$(COMPILE_TARGET)" ]; then \
			args+=("$(COMPILE_TARGET)"); \
		fi; \
		if [ "$(COMPILE_STRATEGY)" = "slurm" ]; then \
			SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" \
			SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
			SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" \
			SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
			SLURM_DRY_RUN="$(SLURM_DRY_RUN)" \
			SLURM_PARTITION="$(SLURM_PARTITION)" \
			SLURM_ACCOUNT="$(SLURM_ACCOUNT)" \
			SLURM_QOS="$(SLURM_QOS)" \
			./cpp/compile_slurm.sh "$${args[@]}"; \
		else \
			COMPILE_JOBS="$(COMPILE_JOBS)" ./cpp/compile.sh "$${args[@]}"; \
		fi; \
	fi

# Clean targets ----

clean_tmp:
	@$(RM) -r "$(PATH_TMP)"
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --create-dirs

clean_compiled:
	@$(RM) -r "$(PATH_BUILD)"
	@find "$(PATH_CPP)" -mindepth 2 -maxdepth 2 -type f \( -name 'fit_model' -o -name 'fit_model_*' \) -exec $(RM) {} +

clean_links:
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --remove-links

## Clean temporary files, logs and R session files
clean: clean_tmp
	@printf '\nCleaning temporary files...\n'
	@$(RM) -r "$(PATH_LOGS)"
	@$(RM) *.aux *.log *.pdf *.txt *.json
	@$(RM) .Rhistory
	@$(RM) .RData
	@printf 'Cleanup completed.\n\n'

## Clean results, images and generated data for a test or test group
# - usage: make clean_test TEST_SUITE=centering TEST_NAME=<test_or_group>
clean_test: clean
	@if [ -z "$(TEST_SUITE)" ] || [ -z "$(TEST_NAME)" ]; then \
		echo ""; \
		echo "Usage: make clean_test TEST_SUITE=<suite> TEST_NAME=<test_or_group>"; \
		echo ""; \
		echo "Available TEST_SUITEs:"; \
		find tests -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | \
		sed 's/^\(.*\)/- \1 (make clean_test TEST_SUITE=\1 TEST_NAME=<test_or_group>)/'; \
		echo ""; \
		exit 0; \
	else \
		echo "Cleaning test or group: $(TEST_SUITE)/$(TEST_NAME)"; \
		resolved_tests="$$( $(RSCRIPT) src/resolve_test_names.R "$(TEST_SUITE)" "$(TEST_NAME)" )" || exit 1; \
		for test_name in $$resolved_tests; do \
			$(RM) -r "$(PATH_RESULTS)/$(TEST_SUITE)/$$test_name"; \
			$(RM) -r "$(PATH_IMAGES)/$(TEST_SUITE)/$$test_name"; \
			$(RM) -r "$(PATH_TEST_DATA)/$(TEST_SUITE)/$$test_name"; \
		done; \
		$(RM) -r "$(PATH_RESULTS)/$(TEST_SUITE)/aggregate/$(TEST_NAME)"; \
		echo "Cleanup completed for: $(TEST_SUITE)/$(TEST_NAME)"; \
	fi

## DANGER ZONE: Full cleanup of all generated files
distclean: clean clean_compiled
	@echo "Attention! This will remove ALL the additional files and directories generated so far."
	@read -p "Are you sure you want to continue? [y/n]: " confirm && [ "$$confirm" = "y" ] || (echo "Cleanup aborted." && false)
	@$(RSCRIPT) config.R --profile "$(TESTBENCH_PROFILE)" --remove-links
	@echo "Removing additional generated files..."
	@$(RM) -r "$(PATH_IMAGES)"
	@$(RM) -r "$(PATH_RESULTS)"
	@$(RM) -r "$(PATH_TEST_DATA)"
	@$(RM) -r "$(PATH_TMP)"
	@if [ -n "$(PATH_REPO)" ]; then $(RM) -r "$(PATH_REPO)/libraries"; fi
	@$(RM) .env
	@printf 'Additional cleanup completed.\n\n'

# Test targets ----

## Run all the batches of a test with the active profile strategy
# usage: make run_test TEST_SUITE=centering TEST_NAME=test1
ifneq ($(strip $(TEST_SUITE)),)
run_test: MODEL := $(TEST_SUITE)
run_test: compile
endif
run_test: ensure_env
	@if [ -z "$(TEST_SUITE)" ] || [ -z "$(TEST_NAME)" ]; then \
		echo ""; \
		echo "Usage: make run_test TEST_SUITE=<suite> TEST_NAME=<test_name>"; \
		echo ""; \
		echo "Available TEST_SUITEs:"; \
		find tests -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | \
		sed 's/^\(.*\)/- \1 (make run_test TEST_SUITE=\1 TEST_NAME=<test_name>)/'; \
		echo ""; \
		exit 0; \
	else \
		case "$(TEST_EXECUTION_STRATEGY)" in \
			serial) runner=./tests/run_tests.sh ;; \
			parallel) runner=./tests/run_tests_parallel.sh ;; \
			slurm) runner=./tests/run_tests_slurm.sh ;; \
			*) echo "Unknown TEST_EXECUTION_STRATEGY: $(TEST_EXECUTION_STRATEGY). Use serial, parallel, or slurm."; exit 1 ;; \
		esac; \
		echo "Running: $(TEST_NAME) from suite $(TEST_SUITE) using $(TEST_EXECUTION_STRATEGY)"; \
		SLURM_ARRAY_LIMIT="$(SLURM_ARRAY_LIMIT)" \
		SLURM_COMPILE="$(SLURM_COMPILE)" \
		SLURM_AGGREGATE="$(SLURM_AGGREGATE)" \
		SLURM_DRY_RUN="$(SLURM_DRY_RUN)" \
		SLURM_CPUS="$(SLURM_CPUS)" \
		SLURM_MEM="$(SLURM_MEM)" \
		SLURM_TIME="$(SLURM_TIME)" \
		SLURM_MULTI_CPUS="$(SLURM_MULTI_CPUS)" \
		SLURM_MULTI_MEM="$(SLURM_MULTI_MEM)" \
		SLURM_MULTI_TIME="$(SLURM_MULTI_TIME)" \
		SLURM_PARTITION="$(SLURM_PARTITION)" \
		SLURM_ACCOUNT="$(SLURM_ACCOUNT)" \
		SLURM_QOS="$(SLURM_QOS)" \
		SLURM_AGG_CPUS="$(SLURM_AGG_CPUS)" \
		SLURM_AGG_MEM="$(SLURM_AGG_MEM)" \
		SLURM_AGG_TIME="$(SLURM_AGG_TIME)" \
		SLURM_COMPILE_CPUS="$(SLURM_COMPILE_CPUS)" \
		SLURM_COMPILE_MEM="$(SLURM_COMPILE_MEM)" \
		SLURM_COMPILE_TIME="$(SLURM_COMPILE_TIME)" \
		SLURM_COMPILE_JOBS="$(SLURM_COMPILE_JOBS)" \
		SLURM_COMPILE_MODEL="$(SLURM_COMPILE_MODEL)" \
		SLURM_COMPILE_TARGET="$(SLURM_COMPILE_TARGET)" \
		SMOKE_TEST="$(SMOKE_TEST)" \
		"$$runner" "$(TEST_SUITE)" "$(TEST_NAME)"; \
	fi

## Inspect results of a specific test interactively
# Usage: make inspect_results TEST_SUITE=<suite> TEST_NAME=<test_name>
# Lists available result files in tmp/queue/<suite>/<test>, lets you select one,
# and runs the corresponding R scripts to visualize or analyze it.
inspect_results: ensure_env
	@if [ -z "$(TEST_SUITE)" ] || [ -z "$(TEST_NAME)" ]; then \
		printf '\nUsage: make inspect_results TEST_SUITE=<suite> TEST_NAME=<test_name>\n'; \
		echo ""; \
		echo "Available TEST_SUITEs:"; \
		find tests -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | \
		sed 's/^\(.*\)/- \1 (make inspect_results TEST_SUITE=\1 TEST_NAME=<test_name>)/'; \
		echo ""; \
		exit 0; \
	else \
		set -e; \
		set -a; source .env; set +a; \
		queue_directory="$${PATH_QUEUE}/$(TEST_SUITE)/$(TEST_NAME)"; \
		SMOKE_TEST="$(SMOKE_TEST)" $(RSCRIPT) src/init.R "$(TEST_SUITE)" "$(TEST_NAME)"; \
		echo "Available files in $$queue_directory:"; \
		files=($$(ls -1 "$$queue_directory" 2>/dev/null)); \
		if [ $${#files[@]} -eq 0 ]; then \
			echo "No files found in $$queue_directory."; \
			exit 1; \
		fi; \
		count=$${#files[@]}; \
		for i in $$(seq 1 $$count); do \
			echo "  $$i) $${files[$$((i-1))]}"; \
		done; \
		echo ""; \
		read -p "Select a file number: " choice; \
		if [ $$choice -ge 1 ] && [ $$choice -le $$count ]; then \
			selected=$${files[$$((choice-1))]}; \
			echo "Running RScript with selected file: $$selected"; \
			$(RSCRIPT) "tests/$(TEST_SUITE)/inspect_results.R" "$(TEST_NAME)" "$$selected"; \
		else \
			echo "Invalid choice!"; \
			exit 1; \
		fi; \
	fi

# Show available targets and descriptions
# Pretty printing for help (tweak width/color as you like)
HELP_FMT ?= \033[36m- %-24s\033[0m %s\n
help:
	@printf '\nAvailable targets:\n'
	@awk -v fmt="$(HELP_FMT)" '\
/^[a-zA-Z0-9_.-]+:.*##/ { \
  line=$$0; \
  tgt=line; sub(/:.*/,"",tgt); \
  desc=line; sub(/.*##[[:space:]]*/,"",desc); \
  printf fmt, tgt, desc; \
  next \
} \
/^##/ { \
  line=$$0; sub(/^##[[:space:]]*/,"",line); \
  if (desc) desc = desc " " line; else desc = line; \
  next \
} \
/^[a-zA-Z0-9_.-]+:/ { \
  if (desc) { \
    tgt=$$0; sub(/:.*/,"",tgt); \
    printf fmt, tgt, desc; \
    desc=""; \
  } \
  next \
} \
' $(MAKEFILE_LIST)
	@echo ""
