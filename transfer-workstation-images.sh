#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE_PREFIX="localhost/cryosparc"
IMAGE_NAMES=(master workstation hybrid)

usage() {
    cat <<'EOF'
Usage:
  transfer-workstation-images.sh pack OUTPUT_TAR [TAG]
  transfer-workstation-images.sh extract INPUT_TAR [PREFIX]

pack:
  TAG defaults to latest. The three localhost/cryosparc-* images are saved
  into one Docker archive.

extract:
  PREFIX defaults to the input tar basename without its .tar.gz, .tgz, or
  .tar suffix. The output directory contains one Docker archive for each
  image.
EOF
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

archive_prefix() {
    local archive_name

    archive_name="$(basename "$1")"
    case "${archive_name}" in
        *.tar.gz) archive_name="${archive_name%.tar.gz}" ;;
        *.tgz) archive_name="${archive_name%.tgz}" ;;
        *.tar) archive_name="${archive_name%.tar}" ;;
    esac
    printf '%s\n' "${archive_name}"
}

manifest_reference() {
    local archive="$1"
    local image_name="$2"
    local reference

    reference="$(tar -xOf "${archive}" manifest.json | jq -er \
        --arg prefix "${IMAGE_PREFIX}-${image_name}:" \
        '[.[] | .RepoTags[]? | select(startswith($prefix))] | first')" \
        || die "Image ${IMAGE_PREFIX}-${image_name}: not found in ${archive}"
    printf '%s\n' "${reference}"
}

pack_images() {
    local archive="$1"
    local tag="${2:-latest}"
    local image_name
    local reference
    local archive_dir
    local -a references=()

    require_command podman
    [[ -n "${tag}" ]] || die "Image tag must not be empty"

    archive_dir="$(dirname "${archive}")"
    mkdir -p "${archive_dir}"

    for image_name in "${IMAGE_NAMES[@]}"; do
        reference="${IMAGE_PREFIX}-${image_name}:${tag}"
        podman image exists "${reference}" \
            || die "Image not found: ${reference}"
        references+=("${reference}")
    done

    podman save \
        --format docker-archive \
        --multi-image-archive \
        --output "${archive}" \
        "${references[@]}"
    printf 'Saved %s\n' "${archive}"
}

extract_images() {
    local archive="$1"
    local prefix="${2:-$(archive_prefix "${archive}")}"
    local image_name
    local reference
    local output

    require_command skopeo
    require_command tar
    require_command jq
    [[ -f "${archive}" ]] || die "Input archive not found: ${archive}"
    [[ -n "${prefix}" ]] || die "Output prefix must not be empty"

    mkdir -p "${prefix}"
    for image_name in "${IMAGE_NAMES[@]}"; do
        reference="$(manifest_reference "${archive}" "${image_name}")"
        output="${prefix}/cryosparc-${image_name}.tar"
        skopeo copy \
            "docker-archive:${archive}:${reference}" \
            "docker-archive:${output}:${reference}"
        printf 'Extracted %s to %s\n' "${reference}" "${output}"
    done
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    usage
    exit 0
fi

[[ $# -ge 2 ]] || {
    usage >&2
    exit 2
}

mode="$1"
shift
case "${mode}" in
    pack)
        [[ $# -ge 1 && $# -le 2 ]] || {
            usage >&2
            exit 2
        }
        pack_images "$@"
        ;;
    extract)
        [[ $# -ge 1 && $# -le 2 ]] || {
            usage >&2
            exit 2
        }
        extract_images "$@"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Unsupported mode: %s\n' "${mode}" >&2
        usage >&2
        exit 2
        ;;
esac
