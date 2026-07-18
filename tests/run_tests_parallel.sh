#!/bin/bash
set -euo pipefail

# $1: test suite name
# $2: test name


start=$(date +%s.%N)
CURRENT_STAGE="startup"
CURRENT_OPTION=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
  echo "Error: .env not found. Run: make build PROFILE=<profile>"
  exit 1
fi

set -a
source "${PROJECT_DIR}/.env"
set +a

export OMP_NUM_THREADS="1"
export OPENBLAS_NUM_THREADS="1"
export VECLIB_MAXIMUM_THREADS="1"

cd "${PATH_REPO}"

# Cap parallel workers when the profile declares a smaller machine budget.
MAX_PARALLEL_CORES="${MULTITHREAD_CPUS:-}"

# Define the total number of CPU cores
if command -v sysctl >/dev/null 2>&1 && sysctl -n hw.physicalcpu >/dev/null 2>&1; then
  TOTAL_CORES=$(sysctl -n hw.physicalcpu)
elif command -v nproc >/dev/null 2>&1; then
  TOTAL_CORES=$(nproc)
else
  TOTAL_CORES=1
fi

# Calculate the number of cores to be used for parallel processing
PARALLEL_CORES=$((TOTAL_CORES - 4))

# Keep smoke tests usable on small or sandboxed machines.
if [ "$PARALLEL_CORES" -lt 1 ]; then
  PARALLEL_CORES=1
fi

# Ensure that PARALLEL_CORES does not exceed the available high-performance cores
if [[ -n "$MAX_PARALLEL_CORES" && "$MAX_PARALLEL_CORES" =~ ^[0-9]+$ &&
      "$PARALLEL_CORES" -gt "$MAX_PARALLEL_CORES" ]]; then
  PARALLEL_CORES="$MAX_PARALLEL_CORES"
fi


###############################################################################


TEST_SUITE="$1"
REQUESTED_TEST_NAME="$2"
CURRENT_STAGE="initializing ${TEST_SUITE}/${REQUESTED_TEST_NAME}"

Rscript src/init.R "${TEST_SUITE}" "${REQUESTED_TEST_NAME}" || {
    echo "run_tests_parallel failed during: ${CURRENT_STAGE}" >&2
    exit 1
}

TEST_NAMES=()
while IFS= read -r test_name; do
    TEST_NAMES+=("${test_name}")
done < <(cd "${PATH_REPO}" && Rscript src/resolve_test_names.R "${TEST_SUITE}" "${REQUESTED_TEST_NAME}")

export PATH_REPO
export TEST_SUITE

for test_name in "${TEST_NAMES[@]}"; do
    cd "${PATH_REPO}"
    echo "Preparing child test ${TEST_SUITE}/${test_name}"

    # Set the directory containing the files
    directory="${PATH_QUEUE}/${TEST_SUITE}/${test_name}/"

    # Check if the directory exists
    if [ ! -d "$directory" ]; then
        echo "Directory $directory not found."
        exit 1
    fi

    set +e
    threading_output="$(cd "${PATH_REPO}" && Rscript src/queue_threading_mode.R "${TEST_SUITE}" "${test_name}" 2>&1)"
    threading_status="$?"
    set -e
    if [ "$threading_status" -ne 0 ]; then
        echo "Could not resolve threading mode for ${TEST_SUITE}/${test_name}" >&2
        echo "$threading_output" >&2
        exit "$threading_status"
    fi
    threading="$(printf '%s' "$threading_output" | tail -n 1)"
    echo "Threading mode for ${TEST_SUITE}/${test_name}: ${threading}"
    export TEST_NAME="${test_name}"

    if [[ "${threading}" == "multi" ]]; then
        CURRENT_STAGE="running multi-thread child ${TEST_SUITE}/${test_name}"
        echo "Running ${TEST_SUITE}/${test_name} sequentially; solver thread env pinned to 1"
        cd "$directory" || exit 1
        for file in *; do
            if [ -f "$file" ]; then
                CURRENT_OPTION="${TEST_SUITE}/${test_name}/${file}"
                cd "${PATH_REPO}"
                OMP_NUM_THREADS="1" \
                OPENBLAS_NUM_THREADS="1" \
                VECLIB_MAXIMUM_THREADS="1" \
                    Rscript tests/"${TEST_SUITE}"/main.R "${test_name}" "$file" || {
                        echo "Test option failed: ${TEST_SUITE}/${test_name}/${file}" >&2
                        echo "See logs in: ${PATH_LOGS}/${TEST_SUITE}/${test_name}" >&2
                        exit 1
                    }
                cd "$directory" || exit 1
            fi
        done
        CURRENT_OPTION=""
    else
        CURRENT_STAGE="running single-thread child ${TEST_SUITE}/${test_name}"
        cd "$directory" || exit 1
        option_count="$(find . -maxdepth 1 -type f -name '*.json' | wc -l | tr -d '[:space:]')"
        if [[ "${option_count}" -lt 1 ]]; then
            echo "No option files found for ${TEST_SUITE}/${test_name}." >&2
            exit 1
        fi
        parallel_jobs="${PARALLEL_CORES}"
        if [[ "${parallel_jobs}" -gt "${option_count}" ]]; then
            parallel_jobs="${option_count}"
        fi
        worker_label="workers"
        [[ "${parallel_jobs}" -eq 1 ]] && worker_label="worker"
        echo "Running ${TEST_SUITE}/${test_name} in parallel with ${parallel_jobs} ${worker_label}"
        joblog="${PATH_LOGS}/${TEST_SUITE}/${test_name}/parallel_joblog.tsv"
        mkdir -p "$(dirname "$joblog")"
        # Run tasks in parallel using GNU Parallel
        set +e
        find . -maxdepth 1 -type f -name '*.json' -exec basename {} \; | sort | \
            OMP_NUM_THREADS="1" \
            OPENBLAS_NUM_THREADS="1" \
            VECLIB_MAXIMUM_THREADS="1" \
            parallel -j "$parallel_jobs" --halt soon,fail=1 --joblog "$joblog" \
              'cd "$PATH_REPO" && Rscript tests/"$TEST_SUITE"/main.R "$TEST_NAME" {}'
        parallel_status="$?"
        set -e
        if [ "$parallel_status" -ne 0 ]; then
            failed_jobs="$(awk -F '\t' 'NR > 1 && ($7 != 0 || $8 != 0) { print }' "$joblog")"
            if [[ -n "$failed_jobs" ]]; then
                echo "GNU Parallel reported a failed worker. Joblog: ${joblog}" >&2
                awk -F '\t' 'NR == 1 || ($7 != 0 || $8 != 0) { print }' "$joblog" >&2
                exit "$parallel_status"
            fi
            echo "GNU Parallel returned status ${parallel_status}, but all workers succeeded according to ${joblog}; continuing." >&2
        fi
    fi
done

## Run time complexity analysis
cd "${PATH_REPO}"
CURRENT_STAGE="aggregating ${TEST_SUITE}/${REQUESTED_TEST_NAME}"
Rscript tests/"${TEST_SUITE}"/aggregate_results.R "${REQUESTED_TEST_NAME}" || {
    echo "run_tests_parallel failed during: ${CURRENT_STAGE}" >&2
    exit 1
}


###############################################################################


# End timer
end=$(date +%s.%N)
execution_time=$(echo "$end - $start" | bc)

# Print total execution time
echo ""
echo "Total execution time: $execution_time seconds"
echo ""
