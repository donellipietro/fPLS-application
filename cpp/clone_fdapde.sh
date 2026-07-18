#!/usr/bin/env bash
set -euo pipefail

repository="${1:-}"
outer_branch="${2:-}"
destination="${3:-}"
managed="${FDAPDE_CPP_MANAGED:-true}"

if [[ -z "${repository}" || -z "${outer_branch}" || -z "${destination}" ]]; then
  echo "Usage: $0 <fdaPDE-cpp-repository> <outer-branch> <destination>" >&2
  exit 1
fi

# Unmanaged mode validates an existing checkout without changing Git state.
case "${managed}" in
  0|false|FALSE|no|NO)
    if ! git -C "${destination}" rev-parse --git-dir >/dev/null 2>&1; then
      echo "Error: unmanaged fdaPDE-cpp path is not a git repository: ${destination}" >&2
      exit 1
    fi
    core_dir="${destination}/fdaPDE/core"
    if ! git -C "${core_dir}" rev-parse --git-dir >/dev/null 2>&1; then
      echo "Error: unmanaged fdaPDE/core submodule is unavailable: ${core_dir}" >&2
      exit 1
    fi
    if [[ ! -f "${destination}/fdaPDE/models.h" ]]; then
      echo "Error: unmanaged fdaPDE-cpp headers are unavailable: ${destination}" >&2
      exit 1
    fi

    outer_commit="$(git -C "${destination}" rev-parse HEAD)"
    core_commit="$(git -C "${core_dir}" rev-parse HEAD)"
    printf 'Using unmanaged fdaPDE-cpp at %s (%s); core (%s)\n' \
      "${destination}" "${outer_commit}" "${core_commit}"
    exit 0
    ;;
esac

# Validate the approved outer/core branch pairing before using the outer gitlink.
case "${outer_branch}" in
  develop-Splines|develop_splines)
    core_branch="develop-splines"
    ;;
  develop_RGCCA)
    core_branch="develop-RGCCA"
    ;;
  develop_fPLS)
    core_branch="develop-fPLS"
    ;;
  *)
    echo "Error: no core branch mapping for outer branch ${outer_branch}" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "${destination}")"

if [[ ! -d "${destination}/.git" ]]; then
  if [[ -e "${destination}" ]]; then
    echo "Error: clone destination exists but is not a git repository: ${destination}" >&2
    exit 1
  fi
  git clone --no-checkout "${repository}" "${destination}"
else
  git -C "${destination}" remote set-url origin "${repository}"
fi

outer_remote_ref="refs/remotes/origin/${outer_branch}"
git -C "${destination}" fetch --quiet origin \
  "+refs/heads/${outer_branch}:${outer_remote_ref}"
outer_commit="$(git -C "${destination}" rev-parse "${outer_remote_ref}")"
git -C "${destination}" checkout --quiet -B "${outer_branch}" "${outer_remote_ref}"
git -C "${destination}" branch --quiet \
  --set-upstream-to="origin/${outer_branch}" "${outer_branch}"
core_commit="$(git -C "${destination}" ls-tree "${outer_commit}" fdaPDE/core | awk '{print $3}')"
if [[ -z "${core_commit}" ]]; then
  echo "Error: ${outer_branch} does not record the fdaPDE/core submodule" >&2
  exit 1
fi

# Restore the recorded submodule remote and checkout the outer gitlink.
git -C "${destination}" submodule sync -- fdaPDE/core
git -C "${destination}" submodule update --init --checkout fdaPDE/core

core_dir="${destination}/fdaPDE/core"
core_remote_ref="refs/remotes/origin/${core_branch}"
git -C "${core_dir}" fetch --quiet origin \
  "+refs/heads/${core_branch}:${core_remote_ref}"
mapped_core_commit="$(git -C "${core_dir}" rev-parse "${core_remote_ref}")"
if [[ "${mapped_core_commit}" != "${core_commit}" ]]; then
  echo "Error: ${outer_branch} records core ${core_commit}, but ${core_branch} is ${mapped_core_commit}" >&2
  exit 1
fi

git -C "${core_dir}" checkout --quiet -B "${core_branch}" "${core_remote_ref}"
git -C "${core_dir}" branch --quiet \
  --set-upstream-to="origin/${core_branch}" "${core_branch}"
checked_out_core="$(git -C "${core_dir}" rev-parse HEAD)"
if [[ "${checked_out_core}" != "${core_commit}" ]]; then
  echo "Error: expected core ${core_commit}, checked out ${checked_out_core}" >&2
  exit 1
fi

printf 'Prepared %s at %s (%s); core %s (%s)\n' \
  "${outer_branch}" "${destination}" "${outer_commit}" "${core_branch}" "${core_commit}"
