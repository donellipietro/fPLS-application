#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./cpp/compile_slurm.sh <model_name> [target]
  ./cpp/compile_slurm.sh --all
  ./cpp/compile_slurm.sh --make-help

Options:
  --parsable              Submit asynchronously and print only the job id.
  --dependency JOBID      Add an afterok dependency.
  -h, --help              Show this help.

Environment options:
  SLURM_COMPILE_CPUS      Compile job cpus-per-task (default: MULTITHREAD_CPUS)
  SLURM_COMPILE_MEM       Compile job memory (default: MULTITHREAD_MEM)
  SLURM_COMPILE_TIME      Compile job walltime (default: MULTITHREAD_TIME)
  SLURM_COMPILE_JOBS      Parallel compiler jobs (default: compile cpus)
  SLURM_DRY_RUN           Print sbatch command without submitting (0/1)
  SLURM_PARTITION         Optional Slurm partition
  SLURM_ACCOUNT           Optional Slurm account
  SLURM_QOS               Optional Slurm QoS
USAGE
}

usage_make() {
  cat <<'USAGE'
Usage:
  make compile_slurm MODEL=<model_name> [TARGET=<target>]
  make compile_slurm MODEL=<model_name> TARGET=all
  make compile_all_slurm

Available Slurm compile targets:
USAGE

  if [[ -n "${PATH_CPP:-}" && -d "${PATH_CPP}" ]]; then
    list_models | while IFS= read -r model; do
      list_targets_for_model "${model}"
    done
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${CPP_DIR}/.." && pwd)"
PARSABLE=0
DEPENDENCY=""

list_models() {
  local model_dir model mains

  shopt -s nullglob
  for model_dir in "${PATH_CPP}"/*; do
    [[ -d "${model_dir}" ]] || continue
    model="$(basename "${model_dir}")"
    [[ "${model}" != "include" ]] || continue

    mains=("${model_dir}"/main*.cpp)
    if [[ "${#mains[@]}" -gt 0 ]]; then
      printf '%s\n' "${model}"
    fi
  done | sort
}

binary_name_for_source() {
  local base="$1"
  local stem

  case "${base}" in
    main.cpp)
      printf 'fit_model\n'
      ;;
    main_*.cpp)
      stem="${base#main_}"
      stem="${stem%.cpp}"
      printf 'fit_model_%s\n' "${stem}"
      ;;
    *)
      return 1
      ;;
  esac
}

list_targets_for_model() {
  local model="$1"
  local model_dir="${PATH_CPP}/${model}"
  local mains src base bin

  shopt -s nullglob
  mains=("${model_dir}"/main*.cpp)

  for src in "${mains[@]}"; do
    base="$(basename "${src}")"
    bin="$(binary_name_for_source "${base}")"
    printf -- '- %s: %s -> %s (make compile_slurm MODEL=%s TARGET=%s)\n' \
      "${model}" "${base}" "${bin}" "${model}" "${bin}"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parsable)
      PARSABLE=1
      shift
      ;;
    --dependency)
      if [[ $# -lt 2 ]]; then
        echo "Error: --dependency requires a job id." >&2
        exit 1
      fi
      DEPENDENCY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
  echo "Error: .env not found. Run: make build TESTBENCH_PROFILE=<profile>" >&2
  exit 1
fi

set -a
source "${PROJECT_DIR}/.env"
set +a

if [[ "${1:-}" == "--make-help" ]]; then
  usage_make
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if ! is_truthy "${SLURM_DRY_RUN:-0}" && ! command -v sbatch >/dev/null 2>&1; then
  echo "Error: sbatch not found in PATH." >&2
  exit 1
fi

COMPILE_ARGS=()
JOB_TARGET=""
case "$1" in
  --all)
    COMPILE_ARGS=(--all)
    JOB_TARGET="all"
    ;;
  *)
    COMPILE_ARGS=("$1")
    JOB_TARGET="$1"
    if [[ -n "${2:-}" ]]; then
      COMPILE_ARGS+=("$2")
      JOB_TARGET="${JOB_TARGET}_$2"
    fi
    ;;
esac

CPUS="${SLURM_COMPILE_CPUS:-${COMPILE_CPUS:-${MULTITHREAD_CPUS:-20}}}"
MEM="${SLURM_COMPILE_MEM:-${COMPILE_MEM:-${MULTITHREAD_MEM:-32GB}}}"
TIME="${SLURM_COMPILE_TIME:-${COMPILE_TIME:-${MULTITHREAD_TIME:-04:00:00}}}"
JOBS="${SLURM_COMPILE_JOBS:-${COMPILE_JOBS:-${CPUS}}}"
LOG_DIR="${PATH_LOGS}/slurm/compile"
mkdir -p "${LOG_DIR}"

JOB_SLUG="compile_${JOB_TARGET}"
JOB_SLUG="${JOB_SLUG//[^A-Za-z0-9_]/_}"
JOB_SLUG="${JOB_SLUG:0:48}"

compile_cmd=("./cpp/compile.sh" "${COMPILE_ARGS[@]}")
printf -v compile_cmd_quoted ' %q' "${compile_cmd[@]}"
compile_cmd_quoted="${compile_cmd_quoted# }"

COMPILE_WRAP=$(cat <<EOF
set -euo pipefail

cd '${PATH_REPO}'
set -a
source '${PROJECT_DIR}/.env'
set +a

export OMP_NUM_THREADS="\${OMP_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="\${OPENBLAS_NUM_THREADS:-1}"
export VECLIB_MAXIMUM_THREADS="\${VECLIB_MAXIMUM_THREADS:-1}"

echo '========================================'
echo 'Compiling C++ target: ${JOB_TARGET}'
echo 'Started at:' \$(date)
echo 'Working directory:' \$(pwd)
echo "SLURM_JOB_ID: \${SLURM_JOB_ID:-unset}"
echo "SLURM_CPUS_PER_TASK: \${SLURM_CPUS_PER_TASK:-unset}"
echo "COMPILE_JOBS: ${JOBS}"
COMPILE_JOBS='${JOBS}' ${compile_cmd_quoted}
echo 'Finished at:' \$(date)
echo '========================================'
EOF
)

SBATCH_ARGS=(
  --parsable
  --job-name="tb_${JOB_SLUG}"
  --output="${LOG_DIR}/tb_${JOB_SLUG}_%j.out"
  --error="${LOG_DIR}/tb_${JOB_SLUG}_%j.err"
  --time="${TIME}"
  --mem="${MEM}"
  --cpus-per-task="${CPUS}"
)

if [[ "${PARSABLE}" -eq 0 ]]; then
  SBATCH_ARGS+=(--wait)
fi

if [[ -n "${DEPENDENCY}" ]]; then
  SBATCH_ARGS+=(--dependency="afterok:${DEPENDENCY}")
fi
if [[ -n "${SLURM_PARTITION:-}" ]]; then
  SBATCH_ARGS+=(--partition="${SLURM_PARTITION}")
fi
if [[ -n "${SLURM_ACCOUNT:-}" ]]; then
  SBATCH_ARGS+=(--account="${SLURM_ACCOUNT}")
fi
if [[ -n "${SLURM_QOS:-}" ]]; then
  SBATCH_ARGS+=(--qos="${SLURM_QOS}")
fi
SBATCH_ARGS+=(--wrap="${COMPILE_WRAP}")

if is_truthy "${SLURM_DRY_RUN:-0}"; then
  printf 'sbatch'
  printf ' %q' "${SBATCH_ARGS[@]}"
  printf '\n'
  exit 0
fi

if ! JOB_ID="$(sbatch "${SBATCH_ARGS[@]}")"; then
  echo "Error: Slurm compile job ${JOB_ID:-unknown} failed." >&2
  echo "Logs: ${LOG_DIR}" >&2
  exit 1
fi
if [[ "${PARSABLE}" -eq 1 ]]; then
  printf '%s\n' "${JOB_ID}"
else
  echo "Submitted compile job: ${JOB_ID}"
  echo "Logs: ${LOG_DIR}"
fi
