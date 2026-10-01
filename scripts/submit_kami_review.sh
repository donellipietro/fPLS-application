#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/kami_review_job.pbs"
cd "${PROJECT_DIR}"

is_truthy() {
  case "${1:-}" in 1|true|TRUE|yes|YES|y|Y) return 0 ;; *) return 1 ;; esac
}

# Resolve the private inputs using the Torque profile before reserving a node.
if ! command -v Rscript >/dev/null 2>&1; then
  echo "Error: Rscript not found in PATH; load the Kami R environment before submitting." >&2
  exit 1
fi
if ! command -v parallel >/dev/null 2>&1; then
  echo "Error: GNU Parallel not found in PATH; load it before submitting." >&2
  exit 1
fi
PATH_APPLICATION_DATA="$(Rscript -e 'source("config.R"); cat(get_config("hpc-torque")$PATH_APPLICATION_DATA)')"
export PATH_APPLICATION_DATA
for input in FEMbasis.Rds X_imputed.rds Ycl.rds; do
  if [[ ! -r "${PATH_APPLICATION_DATA}/${input}" ]]; then
    echo "Error: private application input missing or unreadable: ${PATH_APPLICATION_DATA}/${input}" >&2
    exit 1
  fi
done

# Reserve four CPUs for compilation and concurrent single-threaded training-fold fits.
export PBS_MULTI_CPUS="${PBS_MULTI_CPUS:-4}"
export PBS_MULTI_MEM="${PBS_MULTI_MEM:-32gb}"
export PBS_MULTI_TIME="${PBS_MULTI_TIME:-72:00:00}"
export PBS_QUEUE="${PBS_QUEUE:-test}"
export PBS_EXCLUSIVE_RESOURCE="${PBS_EXCLUSIVE_RESOURCE:-place=excl}"
if [[ ! "${PBS_MULTI_CPUS}" =~ ^[1-9][0-9]*$ ]] || (( PBS_MULTI_CPUS > 96 )); then
  echo "Error: PBS_MULTI_CPUS must be between 1 and 96." >&2
  exit 1
fi
case "${PBS_EXCLUSIVE_RESOURCE}" in
  place=excl|place=exclhost) ;;
  *) echo "Error: Kami requires PBS_EXCLUSIVE_RESOURCE=place=excl or place=exclhost." >&2; exit 1 ;;
esac
if ! command -v pbsnodes >/dev/null 2>&1; then
  echo "Error: pbsnodes not found in PATH; submit from Kami." >&2
  exit 1
fi
if ! is_truthy "${PBS_DRY_RUN:-0}" && ! command -v qsub >/dev/null 2>&1; then
  echo "Error: qsub not found in PATH." >&2
  exit 1
fi

# A PBS state of "free" can still contain jobs. Check the complete allocation,
# and match the paper node's 96 logical CPUs and at least 500 GiB of RAM.
SELECTED_HOST="$(pbsnodes -av | awk '
  function check_node() {
    if (!selected && state == "free" && !jobs && assigned_cpus == "0" &&
        assigned_mem == "0kb" && ncpus == "96" && mem ~ /^[0-9]+kb$/ &&
        mem + 0 >= 524288000 && host ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) {
      selected = host
    }
  }
  /^[^[:space:]]/ {
    check_node()
    state = jobs = assigned_cpus = assigned_mem = ncpus = mem = host = ""
    next
  }
  $1 == "state" { state = $3 }
  $1 == "jobs" { jobs = $3 }
  $1 == "resources_assigned.ncpus" { assigned_cpus = $3 }
  $1 == "resources_assigned.mem" { assigned_mem = $3 }
  $1 == "resources_available.ncpus" { ncpus = $3 }
  $1 == "resources_available.mem" { mem = $3 }
  $1 == "resources_available.host" { host = $3 }
  END { check_node(); if (selected) print selected }
')"
if [[ -z "${SELECTED_HOST}" ]]; then
  echo "Error: no completely idle Kami node with 96 CPUs and at least 500 GiB RAM; no job submitted." >&2
  exit 1
fi
printf 'Selected idle node: %s\n' "${SELECTED_HOST}"

RUN_TAG="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="${PROJECT_DIR}/logs/kami/${RUN_TAG}"
export KAMI_RUN_DIR="${RUN_DIR}"

QSUB_ARGS=(-V -N fpls_application -o "${RUN_DIR}/job.out" -e "${RUN_DIR}/job.err")
QSUB_ARGS+=(-l "select=1:ncpus=${PBS_MULTI_CPUS}:mem=${PBS_MULTI_MEM}:host=${SELECTED_HOST}")
QSUB_ARGS+=(-l "walltime=${PBS_MULTI_TIME}")
QSUB_ARGS+=(-q "${PBS_QUEUE}" -l "${PBS_EXCLUSIVE_RESOURCE}")
[[ -n "${PBS_ACCOUNT:-}" ]] && QSUB_ARGS+=(-A "${PBS_ACCOUNT}")

if is_truthy "${PBS_DRY_RUN:-0}"; then
  printf 'mkdir -p %q\n' "${RUN_DIR}"
  printf 'qsub'
  printf ' %q' "${QSUB_ARGS[@]}" "${JOB_SCRIPT}"
  printf '\n'
  exit 0
fi

mkdir -p "${RUN_DIR}"
JOB_ID="$(qsub "${QSUB_ARGS[@]}" "${JOB_SCRIPT}")"
printf '%s\n' "${JOB_ID}" > "${RUN_DIR}/job_id.txt"
printf 'Submitted %s\nRun directory: %s\n' "${JOB_ID}" "${RUN_DIR}"
