#!/usr/bin/env bash
set -euo pipefail

image="${1:-}"

if [[ -z "${image}" ]]; then
  echo "Usage: $0 <image>" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: install Docker Desktop and enable its WSL2 integration." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is installed but its daemon is unavailable." >&2
  exit 1
fi

if docker image inspect "${image}" >/dev/null 2>&1; then
  printf 'Reusing Docker image: %s\n' "${image}"
else
  printf 'Pulling Docker image: %s\n' "${image}"
  docker pull "${image}"
fi

image_id="$(docker image inspect --format '{{.Id}}' "${image}")"
repo_digest="$(docker image inspect --format '{{join .RepoDigests ","}}' "${image}")"
capabilities="$(docker run --rm --entrypoint sh "${image}" -c '
  set -eu
  gxx="$(command -v g++)"
  test -x /usr/bin/time
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
  printf "g++=%s\nEigen=%s (%s)\nIpopt=%s (%s, %s)\n/usr/bin/time=available\n" \
    "${gxx}" "${eigen}" "${eigen_version}" "${ipopt_version}" \
    "${ipopt_include}" "${ipopt_lib}"
')" || {
  echo "Error: Docker image is missing the expected C++ dependency stack." >&2
  exit 1
}

printf 'Docker image: %s\n' "${image}"
printf 'Docker image ID: %s\n' "${image_id}"
printf 'Docker repository digest: %s\n' "${repo_digest:-unavailable}"
printf '%s\n' "${capabilities}"

case "${image}" in
  *:latest)
    echo "Warning: latest is mutable; the local image is reused until removed explicitly." >&2
    ;;
esac
