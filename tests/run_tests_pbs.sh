#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: ./tests/run_tests_pbs.sh <test_suite> <test_name>" >&2
  exit 1
fi
TEST_SUITE="$1"
TEST_NAME="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DRY_RUN="${PBS_DRY_RUN:-0}"

is_truthy() {
  case "${1:-}" in 1|true|TRUE|yes|YES|y|Y) return 0 ;; *) return 1 ;; esac
}

cd "${PROJECT_DIR}"
if [[ ! -f .env ]]; then
  echo "Error: .env not found. Run: make build PROFILE=hpc-torque" >&2
  exit 1
fi
set -a
source .env
set +a

if ! is_truthy "${DRY_RUN}" && ! command -v qsub >/dev/null 2>&1; then
  echo "Error: qsub not found in PATH." >&2
  exit 1
fi
MAX_JOBS="${PBS_MAX_JOBS:-${DEFAULT_MAX_JOBS:-15}}"
if [[ ! "${MAX_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: PBS_MAX_JOBS must be a positive integer." >&2
  exit 1
fi

cd "${PATH_REPO}"
Rscript src/init.R "${TEST_SUITE}" "${TEST_NAME}"
RESOLVED_TEST_NAMES=()
while IFS= read -r name; do
  RESOLVED_TEST_NAMES+=("${name}")
done < <(Rscript src/resolve_test_names.R "${TEST_SUITE}" "${TEST_NAME}")

qsub_job() {
  local script="$1"
  shift
  if is_truthy "${DRY_RUN}"; then
    printf 'qsub' >&2
    printf ' %q' "$@" >&2
    printf ' %q\n' "${script}" >&2
    printf '<dry-run-job-id>\n'
  else
    qsub "$@" "${script}"
  fi
}

safe_name() {
  printf '%s' "$1" | tr -c '[:alnum:]_' '_' | cut -c1-15
}

RUN_JOB_IDS=()
N_TESTS="${#RESOLVED_TEST_NAMES[@]}"
if (( MAX_JOBS < N_TESTS )); then
  echo "Error: PBS_MAX_JOBS (${MAX_JOBS}) must cover the ${N_TESTS} resolved tests." >&2
  exit 1
fi
for TEST_INDEX in "${!RESOLVED_TEST_NAMES[@]}"; do
  RESOLVED_TEST_NAME="${RESOLVED_TEST_NAMES[TEST_INDEX]}"
  QUEUE_DIR="${PATH_QUEUE}/${TEST_SUITE}/${RESOLVED_TEST_NAME}"
  OPTIONS=()
  while IFS= read -r option; do
    OPTIONS+=("${option}")
  done < <(find "${QUEUE_DIR}" -maxdepth 1 -type f -name '*.json' -exec basename {} \; | sort)
  if [[ "${#OPTIONS[@]}" -eq 0 ]]; then
    echo "Error: no JSON option files found in ${QUEUE_DIR}" >&2
    exit 1
  fi

  THREADING="$(Rscript src/queue_threading_mode.R "${TEST_SUITE}" "${RESOLVED_TEST_NAME}")"
  if [[ "${THREADING}" == "multi" ]]; then
    CPUS="${PBS_MULTI_CPUS:-${MULTITHREAD_CPUS:-96}}"
    MEM="${PBS_MULTI_MEM:-${MULTITHREAD_MEM:-512gb}}"
    TIME="${PBS_MULTI_TIME:-${MULTITHREAD_TIME:-12:00:00}}"
  else
    CPUS="${PBS_CPUS:-${DEFAULT_CPUS:-1}}"
    MEM="${PBS_MEM:-${DEFAULT_MEM:-8gb}}"
    TIME="${PBS_TIME:-${DEFAULT_TIME:-04:00:00}}"
  fi

  JOB_BUDGET=$((MAX_JOBS / N_TESTS))
  (( TEST_INDEX < MAX_JOBS % N_TESTS )) && JOB_BUDGET=$((JOB_BUDGET + 1))
  (( JOB_BUDGET < 1 )) && JOB_BUDGET=1
  N_JOBS="${#OPTIONS[@]}"
  (( N_JOBS > JOB_BUDGET )) && N_JOBS="${JOB_BUDGET}"
  LOG_DIR="${PATH_LOGS}/pbs/${TEST_SUITE}/${RESOLVED_TEST_NAME}"
  mkdir -p "${LOG_DIR}"

  for ((worker = 0; worker < N_JOBS; worker++)); do
    MANIFEST="${LOG_DIR}/options_${worker}.txt"
    : > "${MANIFEST}"
    for ((index = worker; index < ${#OPTIONS[@]}; index += N_JOBS)); do
      printf '%s\n' "${OPTIONS[index]}" >> "${MANIFEST}"
    done

    JOB_NAME="$(safe_name "tb_${worker}_${TEST_SUITE}")"
    JOB_SCRIPT="${LOG_DIR}/${JOB_NAME}.pbs"
    sed -e "s|@PATH_REPO@|${PATH_REPO}|g" \
      -e "s|@PROJECT_DIR@|${PROJECT_DIR}|g" \
      -e "s|@MANIFEST@|${MANIFEST}|g" \
      -e "s|@TEST_SUITE@|${TEST_SUITE}|g" \
      -e "s|@TEST_NAME@|${RESOLVED_TEST_NAME}|g" \
      -e "s|@SMOKE_TEST@|${SMOKE_TEST:-0}|g" \
      tests/pbs_job.template > "${JOB_SCRIPT}"

    QSUB_ARGS=(-V -N "${JOB_NAME}" -o "${LOG_DIR}/${JOB_NAME}.out" -e "${LOG_DIR}/${JOB_NAME}.err")
    QSUB_ARGS+=(-l "walltime=${TIME}" -l "nodes=1:ppn=${CPUS}" -l "mem=${MEM}")
    [[ -n "${PBS_QUEUE:-}" ]] && QSUB_ARGS+=(-q "${PBS_QUEUE}")
    [[ -n "${PBS_ACCOUNT:-}" ]] && QSUB_ARGS+=(-A "${PBS_ACCOUNT}")
    JOB_ID="$(qsub_job "${JOB_SCRIPT}" "${QSUB_ARGS[@]}" | tail -n 1)"
    RUN_JOB_IDS+=("${JOB_ID}")
    echo "Submitted ${TEST_SUITE}/${RESOLVED_TEST_NAME} worker $((worker + 1))/${N_JOBS}: ${JOB_ID}"
  done
done

if is_truthy "${PBS_AGGREGATE:-1}"; then
  DEPENDENCIES="$(IFS=:; echo "${RUN_JOB_IDS[*]}")"
  LOG_DIR="${PATH_LOGS}/pbs/${TEST_SUITE}/${TEST_NAME}"
  mkdir -p "${LOG_DIR}"
  AGG_SCRIPT="${LOG_DIR}/aggregate.pbs"
  sed -e "s|@PATH_REPO@|${PATH_REPO}|g" \
    -e "s|@PROJECT_DIR@|${PROJECT_DIR}|g" \
    -e "s|@TEST_SUITE@|${TEST_SUITE}|g" \
    -e "s|@TEST_NAME@|${TEST_NAME}|g" \
    tests/pbs_aggregate.template > "${AGG_SCRIPT}"
  AGG_ID="$(qsub_job "${AGG_SCRIPT}" -V -N "$(safe_name "tb_agg_${TEST_SUITE}")" \
    -o "${LOG_DIR}/aggregate.out" -e "${LOG_DIR}/aggregate.err" \
    -l "walltime=${PBS_TIME:-${DEFAULT_TIME:-04:00:00}}" -l nodes=1:ppn=1 \
    -l "mem=${PBS_MEM:-${DEFAULT_MEM:-8gb}}" -W "depend=afterok:${DEPENDENCIES}" | tail -n 1)"
  echo "Submitted aggregation job: ${AGG_ID}"
fi
