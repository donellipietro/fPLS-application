#!/bin/bash
set -euo pipefail

# $1: test suite name
# $2: test name

start=$(date +%s.%N)

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

###############################################################################


TEST_SUITE="$1"
REQUESTED_TEST_NAME="$2"

Rscript src/init.R "${TEST_SUITE}" "${REQUESTED_TEST_NAME}"

TEST_NAMES=()
while IFS= read -r test_name; do
    TEST_NAMES+=("${test_name}")
done < <(Rscript src/resolve_test_names.R "${TEST_SUITE}" "${REQUESTED_TEST_NAME}")

for test_name in "${TEST_NAMES[@]}"; do
    # Set the directory containing the files
    directory="${PATH_QUEUE}/${TEST_SUITE}/${test_name}/"

    # Check if the directory exists
    if [ ! -d "$directory" ]; then
        echo "Directory $directory not found."
        exit 1
    fi

    echo "Running ${TEST_SUITE}/${test_name} sequentially; solver thread env pinned to 1"

    # Change to the specified directory
    cd "$directory" || exit 1

    # Iterate over the files in the directory
    for file in *; do
        # Check if the item is a file
        if [ -f "$file" ]; then
            # Run RScript with the current file as an argument
            cd "${PATH_REPO}"
            OMP_NUM_THREADS="1" \
            OPENBLAS_NUM_THREADS="1" \
            VECLIB_MAXIMUM_THREADS="1" \
                Rscript tests/"${TEST_SUITE}"/main.R "${test_name}" "$file"
            cd "$directory" || exit 1
        fi
    done
done

## Run time complexity analysis
cd "${PATH_REPO}"
Rscript tests/"${TEST_SUITE}"/aggregate_results.R "${REQUESTED_TEST_NAME}"


###############################################################################


# End timer
end=$(date +%s.%N)
execution_time=$(echo "$end - $start" | bc)

# Print total execution time
echo ""
echo "Total execution time: $execution_time seconds"
echo ""
