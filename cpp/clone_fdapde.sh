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
  echo "Usage: $0 <fdaPDE-cpp-repository> <outer-ref> <destination>" >&2
  exit 1
fi

# validate unmanaged checkouts without changing their git state
case "${managed}" in
  0|false|FALSE|no|NO)
    if [[ ! -f "${destination}/fdaPDE/models.h" ]] ||
       ! git -C "${destination}/fdaPDE/core" rev-parse --git-dir >/dev/null 2>&1; then
      echo "Error: unmanaged fdaPDE-cpp stack is unavailable: ${destination}" >&2
      exit 1
    fi
    outer_commit="$(git -C "${destination}" rev-parse HEAD)"
    core_commit="$(git -C "${destination}/fdaPDE/core" rev-parse HEAD)"
    if [[ -n "${expected_outer_commit}" && "${outer_commit}" != "${expected_outer_commit}" ]] ||
       [[ -n "${expected_core_commit}" && "${core_commit}" != "${expected_core_commit}" ]]; then
      echo "Error: unmanaged fdaPDE-cpp stack does not match the configured commits" >&2
      exit 1
    fi
    printf 'Using unmanaged fdaPDE-cpp at %s (%s); core (%s)\n' \
      "${destination}" "${outer_commit}" "${core_commit}"
    exit 0
    ;;
esac

# a local source supplies unpublished outer commits and the matching core objects
if git -C "${repository}" rev-parse --git-dir >/dev/null 2>&1; then
  repository="$(cd "${repository}" && pwd)"
  core_repository="${core_repository:-${repository}/fdaPDE/core}"
  if [[ "$(cd "${destination}" 2>/dev/null && pwd || true)" == "${repository}" ]]; then
    echo "Error: managed source and destination must be different checkouts" >&2
    exit 1
  fi
fi

# refuse refreshes that would overwrite local edits in either checkout
if git -C "${destination}" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n "$(git -C "${destination}" status --porcelain --ignore-submodules=none)" ]]; then
    echo "Error: fdaPDE-cpp destination has local changes: ${destination}" >&2
    exit 1
  fi
  git -C "${destination}" remote set-url origin "${repository}"
else
  if [[ -e "${destination}" ]]; then
    echo "Error: clone destination exists but is not a git repository: ${destination}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${destination}")"
  git clone --no-checkout "${repository}" "${destination}"
fi

# fetch the pinned commit directly; a local feature branch never needs publishing
outer_ref="${expected_outer_commit:-${outer_branch}}"
git -C "${destination}" fetch --quiet origin "${outer_ref}"
outer_commit="$(git -C "${destination}" rev-parse 'FETCH_HEAD^{commit}')"
core_commit="$(git -C "${destination}" ls-tree "${outer_commit}" fdaPDE/core | awk '{print $3}')"
if [[ -z "${core_commit}" ]] ||
   [[ -n "${expected_core_commit}" && "${core_commit}" != "${expected_core_commit}" ]]; then
  echo "Error: outer ${outer_commit} does not record the configured core commit" >&2
  exit 1
fi
git -C "${destination}" checkout --quiet --detach "${outer_commit}"

# restore exactly the gitlink, with local core objects when supplied by the source
git -C "${destination}" submodule sync -- fdaPDE/core
if [[ -n "${core_repository}" ]]; then
  git -C "${destination}" config submodule.fdaPDE/core.url "${core_repository}"
  if git -C "${destination}/fdaPDE/core" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${destination}/fdaPDE/core" remote set-url origin "${core_repository}"
  fi
fi
git -C "${destination}" -c protocol.file.allow=always \
  submodule update --init --checkout fdaPDE/core
if [[ "$(git -C "${destination}/fdaPDE/core" rev-parse HEAD)" != "${core_commit}" ]]; then
  echo "Error: prepared core does not match the outer gitlink" >&2
  exit 1
fi
printf 'Prepared %s at %s (%s); core (%s)\n' \
  "${outer_branch}" "${destination}" "${outer_commit}" "${core_commit}"
