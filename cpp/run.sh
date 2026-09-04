#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./cpp/run.sh [--quiet] [--workdir DIR] -- <command> [args...]
  ./cpp/run.sh --describe
USAGE
}

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${CPP_DIR}/.." && pwd)"
QUIET=0
DESCRIBE=0
WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --describe) DESCRIBE=1; shift ;;
    --workdir|--cwd)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires a directory." >&2; exit 1; }
      WORKDIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
  echo "Error: .env not found. Run: make build PROFILE=<profile>" >&2
  exit 1
fi
set -a
source "${PROJECT_DIR}/.env"
set +a

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-1}"
WORKDIR="${WORKDIR:-${PATH_REPO:-${PROJECT_DIR}}}"

if [[ "${DESCRIBE}" -eq 1 || "${QUIET}" -eq 0 ]]; then
  echo "Runtime: host"
  echo "Working directory: ${WORKDIR}"
fi
[[ "${DESCRIBE}" -eq 0 ]] || exit 0
[[ $# -gt 0 ]] || { usage >&2; exit 1; }

cd "${WORKDIR}"
exec "$@"
