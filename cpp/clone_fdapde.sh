#!/usr/bin/env bash
set -euo pipefail

repository="${1:-}"
outer_branch="${2:-}"
destination="${3:-}"
managed="${FDAPDE_CPP_MANAGED:-true}"
core_repository="${FDAPDE_CORE_REPOSITORY:-}"
expected_outer_commit="${FDAPDE_CPP_COMMIT:-}"
expected_core_commit="${FDAPDE_CORE_COMMIT:-}"

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
    if [[ -n "${expected_outer_commit}" && "${outer_commit}" != "${expected_outer_commit}" ]]; then
      echo "Error: expected outer ${expected_outer_commit}, found ${outer_commit}" >&2
      exit 1
    fi
    if [[ -n "${expected_core_commit}" && "${core_commit}" != "${expected_core_commit}" ]]; then
      echo "Error: expected core ${expected_core_commit}, found ${core_commit}" >&2
      exit 1
    fi
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
    core_branch="codex/fpls-stable-parser"
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
outer_tip="$(git -C "${destination}" rev-parse "${outer_remote_ref}")"
outer_commit="${outer_tip}"
if [[ -n "${expected_outer_commit}" ]]; then
  if ! git -C "${destination}" cat-file -e "${expected_outer_commit}^{commit}" 2>/dev/null; then
    echo "Error: expected outer commit is unavailable: ${expected_outer_commit}" >&2
    exit 1
  fi
  if ! git -C "${destination}" merge-base --is-ancestor "${expected_outer_commit}" "${outer_remote_ref}"; then
    echo "Error: expected outer ${expected_outer_commit} is not on ${outer_branch}" >&2
    exit 1
  fi
  outer_commit="${expected_outer_commit}"
fi
git -C "${destination}" checkout --quiet -B "${outer_branch}" "${outer_commit}"
git -C "${destination}" branch --quiet \
  --set-upstream-to="origin/${outer_branch}" "${outer_branch}"
core_commit="$(git -C "${destination}" ls-tree "${outer_commit}" fdaPDE/core | awk '{print $3}')"
if [[ -z "${core_commit}" ]]; then
  echo "Error: ${outer_branch} does not record the fdaPDE/core submodule" >&2
  exit 1
fi
if [[ -n "${expected_core_commit}" && "${core_commit}" != "${expected_core_commit}" ]]; then
  echo "Error: outer ${outer_commit} records core ${core_commit}, expected ${expected_core_commit}" >&2
  exit 1
fi

# Restore the recorded submodule remote and checkout the outer gitlink.
git -C "${destination}" submodule sync -- fdaPDE/core
if [[ -n "${core_repository}" ]]; then
  git -C "${destination}" config submodule.fdaPDE/core.url "${core_repository}"
  if git -C "${destination}/fdaPDE/core" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${destination}/fdaPDE/core" remote set-url origin "${core_repository}"
  fi
fi
git -C "${destination}" -c protocol.file.allow=always \
  submodule update --init --checkout fdaPDE/core

core_dir="${destination}/fdaPDE/core"
core_remote_ref="refs/remotes/origin/${core_branch}"
git -C "${core_dir}" fetch --quiet origin \
  "+refs/heads/${core_branch}:${core_remote_ref}"
mapped_core_commit="$(git -C "${core_dir}" rev-parse "${core_remote_ref}")"
if [[ -z "${expected_outer_commit}" && "${mapped_core_commit}" != "${core_commit}" ]]; then
  echo "Error: ${outer_branch} records core ${core_commit}, but ${core_branch} is ${mapped_core_commit}" >&2
  exit 1
fi
if [[ -n "${expected_outer_commit}" ]] &&
   ! git -C "${core_dir}" merge-base --is-ancestor "${core_commit}" "${core_remote_ref}"; then
  echo "Error: recorded core ${core_commit} is not on ${core_branch}" >&2
  exit 1
fi

git -C "${core_dir}" checkout --quiet -B "${core_branch}" "${core_commit}"
git -C "${core_dir}" branch --quiet \
  --set-upstream-to="origin/${core_branch}" "${core_branch}"
checked_out_core="$(git -C "${core_dir}" rev-parse HEAD)"
if [[ "${checked_out_core}" != "${core_commit}" ]]; then
  echo "Error: expected core ${core_commit}, checked out ${checked_out_core}" >&2
  exit 1
fi

printf 'Prepared %s at %s (%s); core %s (%s)\n' \
  "${outer_branch}" "${destination}" "${outer_commit}" "${core_branch}" "${core_commit}"
