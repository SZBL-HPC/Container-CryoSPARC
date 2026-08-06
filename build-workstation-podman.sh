#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
PODMAN_BIN="${PODMAN_BIN:-podman}"
IMAGE_NAME="${IMAGE_NAME:-localhost/cryosparc-workstation:latest}"
CUDA_IMAGE="${CUDA_IMAGE:-nvidia/cuda:12.8.2-base-ubuntu24.04}"
WORKER_NOGPU="${CRYOSPARC_WORKER_NOGPU:-true}"

if ! command -v "${PODMAN_BIN}" >/dev/null 2>&1; then
    printf 'Podman executable not found: %s\n' "${PODMAN_BIN}" >&2
    exit 1
fi

INITIAL_PASSWORD="${CRYOSPARC_INITIAL_PASSWORD:-Passw0rd}"
if [[ "${INITIAL_PASSWORD}" == Passw0rd ]]; then
    printf 'Warning: using the default initial password; set CRYOSPARC_INITIAL_PASSWORD for production.\n' >&2
fi

BUILD_ARGS=(
    --build-arg "CUDA_IMAGE=${CUDA_IMAGE}"
    --build-arg "CRYOSPARC_INITIAL_PASSWORD=${INITIAL_PASSWORD}"
    --build-arg "CRYOSPARC_WORKER_NOGPU=${WORKER_NOGPU}"
)

for name in \
    CRYOSPARC_INITIAL_EMAIL \
    CRYOSPARC_INITIAL_USERNAME \
    CRYOSPARC_INITIAL_FIRSTNAME \
    CRYOSPARC_INITIAL_LASTNAME \
    CRYOSPARC_BUILD_LICENSE_ID; do
    if [[ -n "${!name:-}" ]]; then
        BUILD_ARGS+=(--build-arg "${name}=${!name}")
    fi
done

exec "${PODMAN_BIN}" build \
    --format docker \
    --file "${ROOT_DIR}/containers/workstation/Dockerfile" \
    --tag "${IMAGE_NAME}" \
    "${BUILD_ARGS[@]}" \
    "${ROOT_DIR}"
