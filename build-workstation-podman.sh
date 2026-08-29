#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
DOCKERFILE_PATH="${ROOT_DIR}/containers/workstation/Dockerfile"

usage() {
    printf 'Usage: %s [--target master|workstation|hybrid] [--run]\n' "$0"
}

RUN_BUILD=false
TARGET=""
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
    BUILD_TARGETS=("${TARGET}")
else
    BUILD_TARGETS=(master workstation hybrid)
fi

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
    printf 'Dockerfile not found: %s\n' "${DOCKERFILE_PATH}" >&2
    exit 1
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
)

for name in CRYOSPARC_BUILD_LICENSE_ID CRYOSPARC_CLUSTER_HOSTS; do
    if [[ -n "${!name:-}" ]]; then
        BUILD_ARGS+=(--build-arg "${name}=${!name}")
    fi
done

build_target() {
    local target="$1"
    local image_name
    local -a build_command

    case "${target}" in
        master) image_name="${MASTER_IMAGE_NAME}" ;;
        workstation) image_name="${WORKSTATION_IMAGE_NAME}" ;;
        hybrid) image_name="${HYBRID_IMAGE_NAME}" ;;
    esac

    build_command=(
        "${PODMAN_BIN}" build
        --format docker
        --platform linux/amd64
        --target "${target}"
        --file "${DOCKERFILE_PATH}"
        --tag "${image_name}"
        "${BUILD_ARGS[@]}"
        "${ROOT_DIR}"
    )

    printf '%q ' "${build_command[@]}"
    printf '\n'

    if [[ "${RUN_BUILD}" == true ]]; then
        "${build_command[@]}"
    fi
}

for target in "${BUILD_TARGETS[@]}"; do
    build_target "${target}"
done
