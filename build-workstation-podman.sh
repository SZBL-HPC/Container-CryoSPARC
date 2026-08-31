#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
DOCKERFILE_PATH="${ROOT_DIR}/containers/cryosparc5/Dockerfile"

usage() {
    printf 'Usage: %s [--target master|workstation|hybrid] [--tags tag[,tag...]] [--run]\n' "$0"
}

RUN_BUILD=false
TARGET=""
EXTRA_TAGS=()

append_tags() {
    local value="$1"
    local -a tags

    if [[ -z "${value}" || "${value}" == ,* || "${value}" == *, || "${value}" == *,,* ]]; then
        printf 'Tags must be a comma-separated list of non-empty values: %s\n' "${value}" >&2
        exit 2
    fi

    IFS=',' read -r -a tags <<< "${value}"
    EXTRA_TAGS+=("${tags[@]}")
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            shift
            if [[ $# -eq 0 ]]; then
                usage >&2
                exit 2
            fi
            TARGET="$1"
            ;;
        --tags|-t)
            shift
            if [[ $# -eq 0 ]]; then
                usage >&2
                exit 2
            fi
            append_tags "$1"
            ;;
        --tags=*)
            append_tags "${1#*=}"
            ;;
        --run)
            RUN_BUILD=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n "${TARGET}" ]]; then
    case "${TARGET}" in
        master|workstation|hybrid)
            ;;
        *)
            printf 'Unsupported build target: %s (expected master, workstation, or hybrid)\n' "${TARGET}" >&2
            exit 2
            ;;
    esac
fi

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
    printf 'Dockerfile not found: %s\n' "${DOCKERFILE_PATH}" >&2
    exit 1
fi

PKG_DIR="${ROOT_DIR}/pkg"
MASTER_PACKAGE="${PKG_DIR}/cryosparc_master.tar.gz"
WORKER_PACKAGE="${PKG_DIR}/cryosparc_worker.tar.gz"
WORKER_PATCH="${PKG_DIR}/cryosparc_worker_patch.tar.gz"
UPDATE_PACKAGES="${ROOT_DIR}/update-packages.sh"

if [[ ! -f "${MASTER_PACKAGE}" && ! -f "${WORKER_PACKAGE}" ]]; then
    if [[ ! -f "${UPDATE_PACKAGES}" ]]; then
        printf 'Package updater not found: %s\n' "${UPDATE_PACKAGES}" >&2
        exit 1
    fi
    printf 'No CryoSPARC packages found in %s; running %s\n' \
        "${PKG_DIR}" "${UPDATE_PACKAGES}"
    bash "${UPDATE_PACKAGES}"
fi

HAS_MASTER_PACKAGE=false
HAS_WORKER_PACKAGE=false
if [[ -f "${MASTER_PACKAGE}" ]]; then
    HAS_MASTER_PACKAGE=true
fi
if [[ -f "${WORKER_PACKAGE}" ]]; then
    HAS_WORKER_PACKAGE=true
fi

if [[ "${HAS_MASTER_PACKAGE}" == false && "${HAS_WORKER_PACKAGE}" == true ]]; then
    printf 'Worker package exists without master package: %s\n' "${WORKER_PACKAGE}" >&2
    exit 1
fi
if [[ "${HAS_MASTER_PACKAGE}" == false ]]; then
    printf 'Master package not found: %s\n' "${MASTER_PACKAGE}" >&2
    exit 1
fi
if [[ "${HAS_WORKER_PACKAGE}" == false && -f "${WORKER_PATCH}" ]]; then
    printf 'Worker patch exists without worker package: %s\n' "${WORKER_PATCH}" >&2
    exit 1
fi

if [[ -n "${TARGET}" ]]; then
    if [[ "${TARGET}" != master && "${HAS_WORKER_PACKAGE}" == false ]]; then
        printf '%s target requires the worker package: %s\n' \
            "${TARGET}" "${WORKER_PACKAGE}" >&2
        exit 1
    fi
    BUILD_TARGETS=("${TARGET}")
elif [[ "${HAS_WORKER_PACKAGE}" == true ]]; then
    BUILD_TARGETS=(master workstation hybrid)
else
    BUILD_TARGETS=(master)
fi

MASTER_IMAGE_NAME="${MASTER_IMAGE_NAME:-localhost/cryosparc-master:latest}"
WORKSTATION_IMAGE_NAME="${WORKSTATION_IMAGE_NAME:-localhost/cryosparc-workstation:latest}"
HYBRID_IMAGE_NAME="${HYBRID_IMAGE_NAME:-localhost/cryosparc-hybrid:latest}"
if [[ -n "${IMAGE_NAME:-}" ]]; then
    if [[ -z "${TARGET}" ]]; then
        printf 'IMAGE_NAME requires --target when building all images.\n' >&2
        exit 2
    fi
    case "${TARGET}" in
        master) MASTER_IMAGE_NAME="${IMAGE_NAME}" ;;
        workstation) WORKSTATION_IMAGE_NAME="${IMAGE_NAME}" ;;
        hybrid) HYBRID_IMAGE_NAME="${IMAGE_NAME}" ;;
    esac
fi
PODMAN_BIN="${PODMAN_BIN:-podman}"
CUDA_IMAGE="${CUDA_IMAGE:-nvidia/cuda:12.8.2-base-ubuntu24.04}"
WORKER_NOGPU="${CRYOSPARC_WORKER_NOGPU:-true}"

if [[ "${RUN_BUILD}" == true ]] && ! command -v "${PODMAN_BIN}" >/dev/null 2>&1; then
    printf 'Podman executable not found: %s\n' "${PODMAN_BIN}" >&2
    exit 1
fi

BUILD_ARGS=(
    --build-arg "CUDA_IMAGE=${CUDA_IMAGE}"
    --build-arg "CRYOSPARC_WORKER_NOGPU=${WORKER_NOGPU}"
    --build-arg "CRYOSPARC_INCLUDE_WORKER=${HAS_WORKER_PACKAGE}"
)

for name in CRYOSPARC_BUILD_LICENSE_ID CRYOSPARC_CLUSTER_HOSTS; do
    if [[ -n "${!name:-}" ]]; then
        BUILD_ARGS+=(--build-arg "${name}=${!name}")
    fi
done

build_target() {
    local target="$1"
    local image_name
    local image_prefix
    local -a build_command

    case "${target}" in
        master) image_name="${MASTER_IMAGE_NAME}" ;;
        workstation) image_name="${WORKSTATION_IMAGE_NAME}" ;;
        hybrid) image_name="${HYBRID_IMAGE_NAME}" ;;
    esac
    image_prefix="${image_name%:*}"

    build_command=(
        "${PODMAN_BIN}" build
        --format docker
        --target "${target}"
        --file "${DOCKERFILE_PATH}"
        --tag "${image_name}"
    )
    if (( ${#EXTRA_TAGS[@]} > 0 )); then
        for tag in "${EXTRA_TAGS[@]}"; do
            build_command+=(--tag "${image_prefix}:${tag}")
        done
    fi
    build_command+=("${BUILD_ARGS[@]}" "${ROOT_DIR}")

    printf '%q ' "${build_command[@]}"
    printf '\n'

    if [[ "${RUN_BUILD}" == true ]]; then
        "${build_command[@]}"
    fi
}

for target in "${BUILD_TARGETS[@]}"; do
    build_target "${target}"
done
