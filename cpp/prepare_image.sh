#!/usr/bin/env bash
set -euo pipefail

source_uri="${1:-}"
destination="${2:-}"

if [[ -z "${source_uri}" || -z "${destination}" ]]; then
  echo "Usage: $0 <source-uri> <destination.sif>" >&2
  exit 1
fi

if command -v apptainer >/dev/null 2>&1; then
  runtime="apptainer"
elif command -v singularity >/dev/null 2>&1; then
  runtime="singularity"
else
  echo "Error: install Apptainer or SingularityCE to prepare ${destination}" >&2
  exit 1
fi

mkdir -p "$(dirname "${destination}")"
if [[ -f "${destination}" ]]; then
  printf 'Reusing container image: %s\n' "${destination}"
else
  printf 'Pulling container image: %s\n' "${source_uri}"
  "${runtime}" pull "${destination}" "${source_uri}"
fi

if ! "${runtime}" inspect "${destination}" >/dev/null; then
  echo "Error: invalid container image: ${destination}" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  image_digest="$(sha256sum "${destination}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  image_digest="$(shasum -a 256 "${destination}" | awk '{print $1}')"
else
  image_digest="unavailable"
fi

capabilities="$("${runtime}" exec "${destination}" sh -c '
  set -eu
  gxx="$(command -v g++)"
  rscript="$(command -v Rscript || true)"
  test -n "${rscript}" || rscript="not found (host R is required)"
  eigen="/usr/include/eigen3"
  test -f "${eigen}/Eigen/Core"
  eigen_version="$(awk '\''
    /^#define EIGEN_WORLD_VERSION / { world = $3 }
    /^#define EIGEN_MAJOR_VERSION / { major = $3 }
    /^#define EIGEN_MINOR_VERSION / { minor = $3 }
    END { print world "." major "." minor }
  '\'' "${eigen}/Eigen/src/Core/util/Macros.h")"
  ipopt_version="$(pkg-config --modversion ipopt)"
  ipopt_include="$(pkg-config --variable=includedir ipopt)"
  ipopt_lib="$(pkg-config --variable=libdir ipopt)"
  printf "g++=%s\nEigen=%s (%s)\nIpopt=%s (%s, %s)\nRscript=%s\n" \
    "${gxx}" "${eigen}" "${eigen_version}" "${ipopt_version}" \
    "${ipopt_include}" "${ipopt_lib}" "${rscript}"
')" || {
  echo "Error: container is missing the expected C++ dependency stack" >&2
  exit 1
}

printf 'Container runtime: %s\n' "$("${runtime}" --version)"
printf 'Configured source: %s\n' "${source_uri}"
printf 'Container path: %s\n' "${destination}"
printf 'Container SIF SHA256: %s\n' "${image_digest}"
printf '%s' "${capabilities}"
printf '\n'

case "${source_uri}" in
  *:latest)
    echo "Warning: latest is mutable; this SIF is reused until removed explicitly." >&2
    ;;
esac
