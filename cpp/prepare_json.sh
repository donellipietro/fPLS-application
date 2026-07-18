#!/usr/bin/env bash
set -euo pipefail

repository="https://github.com/nlohmann/json.git"
ref="v3.12.0"
commit="55f93686c01528224f448c19128836e7df245f72"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-${project_dir}/libraries/nlohmann-json}"
version_header="${destination}/include/nlohmann/detail/abi_macros.hpp"

mkdir -p "$(dirname "${destination}")"

if [[ ! -d "${destination}/.git" ]]; then
  if [[ -e "${destination}" ]]; then
    echo "Error: JSON destination exists but is not a git repository: ${destination}" >&2
    exit 1
  fi
  git -c advice.detachedHead=false clone --depth 1 --branch "${ref}" \
    "${repository}" "${destination}"
else
  origin="$(git -C "${destination}" remote get-url origin 2>/dev/null || true)"
  if [[ "${origin}" != "${repository}" ]]; then
    echo "Error: expected JSON origin ${repository}, found ${origin:-none}" >&2
    exit 1
  fi
fi

if [[ -n "$(git -C "${destination}" status --porcelain)" ]]; then
  echo "Error: JSON clone has local changes: ${destination}" >&2
  exit 1
fi

resolved_commit="$(
  git -C "${destination}" rev-parse "refs/tags/${ref}^{commit}" 2>/dev/null || true
)"
if [[ -n "${resolved_commit}" && "${resolved_commit}" != "${commit}" ]]; then
  echo "Error: ${ref} resolved to ${resolved_commit}, expected ${commit}" >&2
  exit 1
fi
if [[ -z "${resolved_commit}" ]]; then
  git -C "${destination}" fetch --quiet --depth 1 origin \
    "refs/tags/${ref}:refs/tags/${ref}"
  resolved_commit="$(git -C "${destination}" rev-parse "refs/tags/${ref}^{commit}")"
fi

if [[ "${resolved_commit}" != "${commit}" ]]; then
  echo "Error: ${ref} resolved to ${resolved_commit}, expected ${commit}" >&2
  exit 1
fi

checked_out_commit="$(git -C "${destination}" rev-parse HEAD)"
if [[ "${checked_out_commit}" != "${commit}" ]]; then
  git -C "${destination}" checkout --quiet --detach "${commit}"
  checked_out_commit="$(git -C "${destination}" rev-parse HEAD)"
fi
if [[ "${checked_out_commit}" != "${commit}" ]]; then
  echo "Error: checked out JSON ${checked_out_commit}, expected ${commit}" >&2
  exit 1
fi
if [[ ! -f "${destination}/include/nlohmann/json.hpp" || ! -f "${version_header}" ]]; then
  echo "Error: nlohmann/json headers not found in ${destination}/include" >&2
  exit 1
fi

version="$(awk '
  /^#define NLOHMANN_JSON_VERSION_MAJOR / { major = $3 }
  /^#define NLOHMANN_JSON_VERSION_MINOR / { minor = $3 }
  /^#define NLOHMANN_JSON_VERSION_PATCH / { patch = $3 }
  END { print major "." minor "." patch }
' "${version_header}")"
if [[ "${version}" != "3.12.0" ]]; then
  echo "Error: checked out nlohmann/json ${version}, expected 3.12.0" >&2
  exit 1
fi

printf 'Prepared nlohmann/json %s at %s (%s)\n' \
  "${ref}" "${destination}" "${commit}"
