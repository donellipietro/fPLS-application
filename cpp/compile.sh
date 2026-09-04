#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./cpp/compile.sh <model_name> [target]
  ./cpp/compile.sh --all

Target can be an executable name, source file, or source stem:
  fit_model
  main.cpp
  model_name

Use target "all" to compile every main*.cpp in the model directory.
If target is omitted, "all" is used.
USAGE

  if [[ -n "${PATH_CPP:-}" && -d "${PATH_CPP}" ]]; then
    echo ""
    echo "Available compile targets:"
    list_models | while IFS= read -r model; do
      list_targets_for_model "${model}" "shell"
    done
  fi
}

usage_make() {
  cat <<'USAGE'
Usage:
  make compile MODEL=<model_name> [TARGET=<target>]
  make compile MODEL=<model_name> TARGET=all
  make compile_all

Available compile targets:
USAGE

  if [[ -n "${PATH_CPP:-}" && -d "${PATH_CPP}" ]]; then
    list_models | while IFS= read -r model; do
      list_targets_for_model "${model}" "make"
    done
  fi
}

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${CPP_DIR}/.." && pwd)"
PATH_NLOHMANN_JSON="${PROJECT_DIR}/libraries/nlohmann-json"

if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
  echo "Error: .env not found. Run: make build TESTBENCH_PROFILE=<profile>" >&2
  exit 1
fi

set -a
source "${PROJECT_DIR}/.env"
set +a

path_required() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "${value}" ]]; then
    echo "Error: ${name} is not set. Check config.R and rebuild .env." >&2
    exit 1
  fi
}

prepare_fdapde() {
  if [[ "${FDAPDE_PREPARED:-0}" == "1" ]]; then
    return
  fi

  # Refresh the profile-selected local stack once per compile invocation.
  path_required FDAPDE_CPP_REPOSITORY
  path_required FDAPDE_CPP_BRANCH
  path_required PATH_FDAPDE_CPP
  "${CPP_DIR}/clone_fdapde.sh" \
    "${FDAPDE_CPP_REPOSITORY}" \
    "${FDAPDE_CPP_BRANCH}" \
    "${PATH_FDAPDE_CPP}"
  PATH_FDAPDE_CORE="${PATH_FDAPDE_CPP}/fdaPDE/core"
  FDAPDE_PREPARED=1
}

prepare_json() {
  if [[ "${JSON_PREPARED:-0}" == "1" ]]; then
    return
  fi

  "${CPP_DIR}/prepare_json.sh" "${PATH_NLOHMANN_JSON}"
  JSON_PREPARED=1
}

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

split_flags() {
  local value="$1"

  if [[ -n "${value}" ]]; then
    read -r -a SPLIT_FLAGS_RESULT <<< "${value}"
  else
    SPLIT_FLAGS_RESULT=()
  fi
}

display_path() {
  local path="$1"

  if [[ "${path}" == "${PROJECT_DIR}" ]]; then
    printf '.'
  elif [[ "${path}" == "${PROJECT_DIR}/"* ]]; then
    printf '%s' "${path#"${PROJECT_DIR}/"}"
  else
    printf '%s' "${path}"
  fi
}

ensure_ipopt_options() {
  local build_dir="$1"
  local src="${PATH_CPP}/ipopt.opt"
  local dst="${build_dir}/ipopt.opt"

  [[ -f "${src}" ]] || return 0

  if [[ -L "${dst}" ]]; then
    ln -sfn "${src}" "${dst}"
  elif [[ -e "${dst}" ]]; then
    echo "Warning: $(display_path "${dst}") exists and is not a symlink; leaving it unchanged." >&2
  else
    ln -s "${src}" "${dst}"
  fi
}

compile_flags() {
  local configured_flags
  local flag

  include_flags=()
  include_flags+=("-I${PATH_NLOHMANN_JSON}/include")
  [[ -n "${PATH_FDAPDE_CPP:-}" ]] && include_flags+=("-I${PATH_FDAPDE_CPP}")
  [[ -n "${PATH_FDAPDE_CORE:-}" ]] && include_flags+=("-I${PATH_FDAPDE_CORE}")
  [[ -n "${PATH_IPOPT_INCLUDE:-}" ]] && include_flags+=("-I${PATH_IPOPT_INCLUDE}")
  [[ -n "${PATH_EIGEN_INCLUDE:-}" ]] && include_flags+=("-I${PATH_EIGEN_INCLUDE}")

  if [[ -n "${CXXFLAGS:-}" ]]; then
    split_flags "${CXXFLAGS}"
    configured_flags=("${SPLIT_FLAGS_RESULT[@]}")
  else
    configured_flags=(
      -O3
      -Wno-psabi
      -std=c++20
      -march=native
      -DFDAPDE_ENABLE_COUT
    )
  fi

  cxx_flags=()
  for flag in "${configured_flags[@]}"; do
    cxx_flags+=("${flag}")
  done
  if [[ "${#include_flags[@]}" -gt 0 ]]; then
    for flag in "${include_flags[@]}"; do
      cxx_flags+=("${flag}")
    done
  fi
  if [[ -n "${LDFLAGS:-}" ]]; then
    split_flags "${LDFLAGS}"
    ld_flags=("${SPLIT_FLAGS_RESULT[@]}")
  else
    ld_flags=()
    [[ -n "${PATH_IPOPT_LIB:-}" ]] && ld_flags+=("-L${PATH_IPOPT_LIB}")
  fi

  if [[ -n "${LDLIBS:-}" ]]; then
    split_flags "${LDLIBS}"
    ld_libs=("${SPLIT_FLAGS_RESULT[@]}")
  else
    ld_libs=()
  fi
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

source_matches_target() {
  local src="$1"
  local target="$2"
  local base stem bin

  base="$(basename "${src}")"
  bin="$(binary_name_for_source "${base}")"
  stem="${base#main_}"
  stem="${stem%.cpp}"

  [[ "${target}" == "${base}" ||
     "${target}" == "${bin}" ||
     "${target}" == "${stem}" ]]
}

list_targets_for_model() {
  local model="$1"
  local style="${2:-make}"
  local model_dir="${PATH_CPP}/${model}"
  local mains src base bin stem

  shopt -s nullglob
  mains=("${model_dir}"/main*.cpp)

  for src in "${mains[@]}"; do
    base="$(basename "${src}")"
    bin="$(binary_name_for_source "${base}")"
    stem="${base#main_}"
    stem="${stem%.cpp}"

    case "${style}" in
      shell)
        printf -- '- %s: %s -> %s (./cpp/compile.sh %q %q)\n' \
          "${model}" "${base}" "${bin}" "${model}" "${bin}"
        ;;
      *)
        printf -- '- %s: %s -> %s (make compile MODEL=%s TARGET=%s)\n' \
          "${model}" "${base}" "${bin}" "${model}" "${bin}"
        ;;
    esac
  done
}

headers_newer_than() {
  local out="$1"
  local newer root

  for root in "${PATH_CPP}" "${PATH_FDAPDE_CPP:-}/fdaPDE" \
    "${PATH_NLOHMANN_JSON}/include"; do
    [[ -d "${root}" ]] || continue
    newer="$(find "${root}" -type f \( -name '*.h' -o -name '*.hpp' \) -newer "${out}" -print -quit)"
    [[ -z "${newer}" ]] || return 0
  done
  return 1
}

normalized_compile_jobs() {
  local value="${COMPILE_JOBS:-${MULTITHREAD_CPUS:-1}}"
  local max_jobs="${1:-}"

  if [[ ! "${value}" =~ ^[0-9]+$ || "${value}" -lt 1 ]]; then
    echo "Warning: invalid COMPILE_JOBS='${value}', using 1." >&2
    value=1
  fi
  if [[ -n "${max_jobs}" && "${value}" -gt "${max_jobs}" ]]; then
    value="${max_jobs}"
  fi

  printf '%s\n' "${value}"
}

compile_one_source() {
  local build_dir="$1"
  local src="$2"
  local base bin out src_display out_display
  local cmd

  base="$(basename "${src}")"
  bin="$(binary_name_for_source "${base}")"
  out="${build_dir}/${bin}"

  if [[ ! -f "${out}" || "${src}" -nt "${out}" ]] ||
      headers_newer_than "${out}"; then
    src_display="$(display_path "${src}")"
    out_display="$(display_path "${out}")"
    echo "- ${src_display}  ==>  ${out_display}"
    cmd=("${CXX:-g++}")
    for flag in "${cxx_flags[@]}"; do
      cmd+=("${flag}")
    done
    cmd+=(-o "${out}" "${src}")
    if [[ "${#ld_flags[@]}" -gt 0 ]]; then
      for flag in "${ld_flags[@]}"; do
        cmd+=("${flag}")
      done
    fi
    if [[ "${#ld_libs[@]}" -gt 0 ]]; then
      for flag in "${ld_libs[@]}"; do
        cmd+=("${flag}")
      done
    fi
    "${CPP_DIR}/run.sh" --quiet -- "${cmd[@]}"
  else
    echo "- $(display_path "${out}") is up to date"
  fi
}

compile_model() {
  local model="$1"
  local target="${2:-}"
  local model_dir="${PATH_CPP}/${model}"
  local build_dir="${PATH_BUILD}/${model}"
  local mains selected_mains src
  local compile_job_limit compile_status pid
  local compile_pids

  prepare_json
  prepare_fdapde

  if [[ ! -d "${model_dir}" ]]; then
    echo "Error: model directory not found: ${model_dir}" >&2
    exit 1
  fi

  shopt -s nullglob
  mains=("${model_dir}"/main*.cpp)
  if [[ "${#mains[@]}" -eq 0 ]]; then
    echo "No main*.cpp found in ${model_dir}" >&2
    exit 1
  fi

  if [[ -z "${target}" || "${target}" == "all" ]]; then
    selected_mains=("${mains[@]}")
  else
    selected_mains=()
    for src in "${mains[@]}"; do
      if source_matches_target "${src}" "${target}"; then
        selected_mains+=("${src}")
      fi
    done

    if [[ "${#selected_mains[@]}" -eq 0 ]]; then
      printf '\nUnknown compile target for cpp/%s: %s\n' "${model}" "${target}" >&2
      printf 'Available targets:\n' >&2
      list_targets_for_model "${model}" "make" >&2
      exit 1
    fi
  fi

  printf '\nCompiling mains in cpp/%s' "${model}"
  if [[ -n "${target}" && "${target}" != "all" ]]; then
    printf ' [%s]' "${target}"
  fi
  printf ' ...\n'
  "${CPP_DIR}/run.sh" --describe
  echo "Compiler: ${CXX:-g++}"

  mkdir -p "${build_dir}"
  ensure_ipopt_options "${build_dir}"
  compile_flags
  compile_job_limit="$(normalized_compile_jobs "${#selected_mains[@]}")"
  echo "Compile jobs: ${compile_job_limit}"

  compile_pids=()
  compile_status=0
  for src in "${selected_mains[@]}"; do
    if [[ "${compile_job_limit}" -gt 1 && "${#selected_mains[@]}" -gt 1 ]]; then
      compile_one_source "${build_dir}" "${src}" &
      compile_pids+=("$!")

      if [[ "${#compile_pids[@]}" -ge "${compile_job_limit}" ]]; then
        if ! wait "${compile_pids[0]}"; then
          compile_status=1
        fi
        compile_pids=("${compile_pids[@]:1}")
      fi
    else
      compile_one_source "${build_dir}" "${src}"
    fi
  done

  if [[ "${#compile_pids[@]}" -gt 0 ]]; then
    for pid in "${compile_pids[@]}"; do
      if ! wait "${pid}"; then
        compile_status=1
      fi
    done
  fi
  if [[ "${compile_status}" -ne 0 ]]; then
    exit "${compile_status}"
  fi

  printf 'All the source files have been compiled!\n\n'
}

path_required PATH_CPP
path_required PATH_BUILD

if [[ $# -eq 1 && -z "${1}" ]]; then
  set --
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --make-help)
    usage_make
    exit 0
    ;;
  --all)
    models=()
    while IFS= read -r model; do
      models+=("${model}")
    done < <(list_models)
    if [[ "${#models[@]}" -eq 0 ]]; then
      echo "No models with main*.cpp found in ${PATH_CPP}" >&2
      exit 1
    fi

    printf '\nCompiling all models in %s...\n' "$(display_path "${PATH_CPP}")"
    for model in "${models[@]}"; do
      compile_model "${model}" "all"
    done
    printf 'All models compiled successfully.\n\n'
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    compile_model "$1" "${2:-}"
    ;;
esac
