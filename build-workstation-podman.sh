#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
DOCKERFILE_PATH="${ROOT_DIR}/containers/workstation/Dockerfile"

usage() {
    printf 'Usage: %s [--run]\n' "$0"
}

RUN_BUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
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

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
    printf 'Dockerfile not found: %s\n' "${DOCKERFILE_PATH}" >&2
    exit 1
fi

IMAGE_NAME="${IMAGE_NAME:-localhost/cryosparc-workstation:latest}"
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

for name in CRYOSPARC_BUILD_LICENSE_ID; do
    if [[ -n "${!name:-}" ]]; then
        BUILD_ARGS+=(--build-arg "${name}=${!name}")
    fi
done

BUILD_COMMAND=(
    "${PODMAN_BIN}" build \
    --format docker \
    --file "${DOCKERFILE_PATH}" \
    --tag "${IMAGE_NAME}" \
    "${BUILD_ARGS[@]}" \
    "${ROOT_DIR}"
)

printf '%q ' "${BUILD_COMMAND[@]}"
printf '\n'

if [[ "${RUN_BUILD}" == true ]]; then
    exec "${BUILD_COMMAND[@]}"
fi
