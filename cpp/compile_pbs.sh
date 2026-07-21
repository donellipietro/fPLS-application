#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: ./cpp/compile_pbs.sh --all | <model> [target]" >&2
  exit 1
fi

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${CPP_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"
if [[ ! -f .env ]]; then
  echo "Error: .env not found. Run: make build PROFILE=hpc-torque" >&2
  exit 1
fi
set -a
source .env
set +a

if ! command -v qsub >/dev/null 2>&1 && [[ "${PBS_COMPILE_DRY_RUN:-0}" != "1" ]]; then
  echo "Error: qsub not found in PATH." >&2
  exit 1
fi

CPUS="${PBS_COMPILE_CPUS:-${COMPILE_CPUS:-4}}"
MEM="${PBS_COMPILE_MEM:-${COMPILE_MEM:-16GB}}"
TIME="${PBS_COMPILE_TIME:-${COMPILE_TIME:-04:00:00}}"
JOBS="${PBS_COMPILE_JOBS:-${CPUS}}"
LOG_DIR="${PATH_LOGS}/pbs/compile"
mkdir -p "${LOG_DIR}"
STAMP="$(date +%Y%m%d_%H%M%S)"
MARKER="${LOG_DIR}/compile_${STAMP}.status"
JOB_SCRIPT="${LOG_DIR}/compile_${STAMP}.pbs"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  "cd '${PATH_REPO}'" \
  "set -a; source '${PROJECT_DIR}/.env'; set +a" \
  "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1" \
  "set +e" \
  "COMPILE_JOBS='${JOBS}' '${PROJECT_DIR}/cpp/compile.sh' $(printf '%q ' "$@")" \
  'status=$?' \
  "printf '%s\\n' \"\${status}\" > '${MARKER}'" \
  'exit "${status}"' > "${JOB_SCRIPT}"

QSUB_ARGS=(-V -N "tb_compile_${STAMP}" -o "${LOG_DIR}/compile_${STAMP}.out" -e "${LOG_DIR}/compile_${STAMP}.err")
QSUB_ARGS+=(-l "walltime=${TIME}" -l "nodes=1:ppn=${CPUS}" -l "mem=${MEM}")
[[ -n "${PBS_QUEUE:-}" ]] && QSUB_ARGS+=(-q "${PBS_QUEUE}")
[[ -n "${PBS_ACCOUNT:-}" ]] && QSUB_ARGS+=(-A "${PBS_ACCOUNT}")

if [[ "${PBS_COMPILE_DRY_RUN:-0}" == "1" ]]; then
  printf 'qsub'
  printf ' %q' "${QSUB_ARGS[@]}" "${JOB_SCRIPT}"
  printf '\n'
  exit 0
fi

JOB_ID="$(qsub "${QSUB_ARGS[@]}" "${JOB_SCRIPT}")"
echo "Submitted compile job: ${JOB_ID}"
echo "Logs: ${LOG_DIR}"
while [[ ! -f "${MARKER}" ]]; do
  sleep 5
done

STATUS="$(<"${MARKER}")"
if [[ "${STATUS}" != "0" ]]; then
  echo "Error: PBS compile job failed with status ${STATUS}." >&2
  exit "${STATUS}"
fi
echo "PBS compilation completed successfully."
