#!/usr/bin/env bash

set -Eeuo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
TMP_DIR="${PKG_DIR}/tmp"
BASE_URL="${CRYOSPARC_LICENSE_SERVER_ADDR:-https://get.cryosparc.com}"
BASE_URL="${BASE_URL%/}"

usage() {
    cat <<'EOF'
Usage:
  pkg/update-packages.sh [LICENSE_ID] [VERSION]
  pkg/update-packages.sh --check [LICENSE_ID]
  pkg/update-packages.sh --list [LICENSE_ID]

Environment overrides:
  CRYOSPARC_LICENSE_ID
  CRYOSPARC_VERSION
  CRYOSPARC_LICENSE_SERVER_ADDR
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

ACTION=update
if [[ "${1:-}" == "--check" || "${1:-}" == "--list" ]]; then
    ACTION="${1#--}"
    shift
fi

LICENSE_ID="${1:-${CRYOSPARC_LICENSE_ID:-}}"
VERSION_REQUEST="${2:-${CRYOSPARC_VERSION:-latest}}"

file_size() {
    local file="$1"
    local size

    if size="$(stat -c %s "${file}" 2>/dev/null)"; then
        printf '%s' "${size}"
    else
        stat -f %z "${file}"
    fi
}

archive_record() {
    local archive="$1"
    local mode="$2"
    local record="$3"

    tar -xOzf "${archive}" "cryosparc_${mode}/${record}" 2>/dev/null \
        | tr -d '\r\n'
}

if [[ -z "${LICENSE_ID}" && -t 0 ]]; then
    read -r -p 'CryoSPARC license ID: ' LICENSE_ID
fi

[[ -n "${LICENSE_ID}" ]] || die 'license ID is required'
[[ "${LICENSE_ID}" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]] \
    || die 'license ID format is invalid'

CURRENT_VERSION=''
if [[ -f "${PKG_DIR}/cryosparc_master.tar.gz" ]]; then
    CURRENT_VERSION="$(archive_record "${PKG_DIR}/cryosparc_master.tar.gz" master version || true)"
fi

versions_request() {
    local endpoint="$1"

    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
        --header 'Content-Type: application/json' \
        --data "{\"version\":\"latest\",\"running_version\":\"${CURRENT_VERSION}\",\"license_id\":\"${LICENSE_ID}\"}" \
        "${BASE_URL}/${endpoint}"
}

if [[ "${ACTION}" == list ]]; then
    printf 'Available versions:\n\n%s\n' "$(versions_request versions/list)"
    exit 0
fi

LATEST_VERSION=''
if [[ "${ACTION}" == check || "${VERSION_REQUEST}" == latest ]]; then
    LATEST_VERSION="$(versions_request versions/latest)"
    [[ "${LATEST_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]] \
        || die "invalid latest version response: ${LATEST_VERSION}"
fi

if [[ "${ACTION}" == check ]]; then
    printf 'Current version: %s\nLatest version: %s\n' \
        "${CURRENT_VERSION:-unknown}" "${LATEST_VERSION}"
    if [[ -n "${CURRENT_VERSION}" && "${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
        printf 'Already up to date.\n'
    else
        printf 'Update available.\n'
    fi
    exit 0
fi

if [[ "${VERSION_REQUEST}" == latest ]]; then
    VERSION="${LATEST_VERSION}"
else
    VERSION="${VERSION_REQUEST}"
fi
[[ "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]] \
    || die "invalid version: ${VERSION}"

mkdir -p "${TMP_DIR}"
TEMP_FILES=()

cleanup() {
    local file
    for file in "${TEMP_FILES[@]}"; do
        rm -f "${file}"
    done
}
trap cleanup EXIT

json_field() {
    local field="$1"
    local payload="$2"

    printf '%s' "${payload}" \
        | tr -d '\r\n' \
        | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

PATCH_JSON="$(curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --get \
    --data-urlencode "license_id=${LICENSE_ID}" \
    "${BASE_URL}/patch_check/${VERSION}")"
PATCH_ID="$(json_field id "${PATCH_JSON}")"
PATCH_NAME="$(json_field name "${PATCH_JSON}")"
PATCH_VERSION="$(json_field applies_to_release "${PATCH_JSON}")"

[[ -n "${PATCH_ID}" ]] || die 'patch response did not contain id'
[[ -n "${PATCH_NAME}" ]] || die 'patch response did not contain name'
[[ "${PATCH_VERSION}" == "${VERSION}" ]] || die "patch applies to ${PATCH_VERSION}, not ${VERSION}"

last_header_value() {
    local header="$1"
    local header_file="$2"

    awk -v wanted="${header}" '
        tolower($0) ~ "^" tolower(wanted) ":" {
            value = $0
            sub(/^[^:]*:[[:space:]]*/, "", value)
            gsub(/\r/, "", value)
        }
        END { print value }
    ' "${header_file}"
}

remote_size() {
    local header_file="$1"
    local range_value
    local length_value

    range_value="$(last_header_value content-range "${header_file}")"
    if [[ "${range_value}" == */* ]]; then
        printf '%s' "${range_value##*/}"
        return
    fi

    length_value="$(last_header_value content-length "${header_file}")"
    printf '%s' "${length_value}"
}

sync_archive() {
    local mode="$1"
    local kind="$2"
    local target="$3"
    local url="$4"
    local expected_version="$5"
    local expected_patch="${6:-}"
    local target_name
    local headers
    local remote_bytes
    local local_bytes
    local local_version=''
    local local_patch=''
    local temp_archive
    local downloaded_version
    local downloaded_patch
    local remote_filename

    target_name="$(basename "${target}")"
    headers="${TMP_DIR}/${target_name}.$$.headers"
    TEMP_FILES+=("${headers}")

    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
        --range 0-0 --dump-header "${headers}" --output /dev/null "${url}"

    remote_bytes="$(remote_size "${headers}")"
    [[ "${remote_bytes}" =~ ^[0-9]+$ ]] || die "remote size unavailable for ${target_name}"
    remote_filename="$(last_header_value content-disposition "${headers}")"
    if [[ -n "${remote_filename}" ]]; then
        printf 'Remote filename for %s: %s\n' "${target_name}" "${remote_filename}"
    fi

    if [[ -f "${target}" ]]; then
        local_bytes="$(file_size "${target}")"
        local_version="$(archive_record "${target}" "${mode}" version || true)"
        local_patch="$(archive_record "${target}" "${mode}" patch || true)"

        if [[ "${local_bytes}" == "${remote_bytes}" \
            && "${local_version}" == "${expected_version}" \
            && ( "${kind}" == package || "${local_patch}" == "${expected_patch}" ) ]]; then
            printf 'Unchanged: %s (%s bytes, version %s%s)\n' \
                "${target_name}" \
                "${local_bytes}" \
                "${local_version}" \
                "${local_patch:+, patch ${local_patch}}"
            return
        fi
    fi

    temp_archive="${TMP_DIR}/${target_name}.$$.download"
    TEMP_FILES+=("${temp_archive}")
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
        --output "${temp_archive}" "${url}"

    if [[ "$(file_size "${temp_archive}")" != "${remote_bytes}" ]]; then
        die "downloaded size mismatch for ${target_name}"
    fi

    downloaded_version="$(archive_record "${temp_archive}" "${mode}" version || true)"
    downloaded_patch="$(archive_record "${temp_archive}" "${mode}" patch || true)"
    [[ "${downloaded_version}" == "${expected_version}" ]] \
        || die "downloaded ${target_name} contains version ${downloaded_version}, expected ${expected_version}"
    if [[ "${kind}" == patch && "${downloaded_patch}" != "${expected_patch}" ]]; then
        die "downloaded ${target_name} contains patch ${downloaded_patch}, expected ${expected_patch}"
    fi

    if [[ -f "${target}" && "${local_version}" == "${downloaded_version}" \
        && ( "${kind}" == package || "${local_patch}" == "${downloaded_patch}" ) ]]; then
        printf 'No semantic update: %s remains version %s%s\n' \
            "${target_name}" \
            "${downloaded_version}" \
            "${downloaded_patch:+, patch ${downloaded_patch}}"
        return
    fi

    chmod 644 "${temp_archive}"
    mv -f "${temp_archive}" "${target}"
    printf 'Updated: %s (%s bytes, version %s%s)\n' \
        "${target_name}" \
        "${remote_bytes}" \
        "${downloaded_version}" \
        "${downloaded_patch:+, patch ${downloaded_patch}}"
}

sync_archive \
    master package \
    "${PKG_DIR}/cryosparc_master.tar.gz" \
    "${BASE_URL}/download/master-${VERSION}/${LICENSE_ID}" \
    "${VERSION}"

sync_archive \
    worker package \
    "${PKG_DIR}/cryosparc_worker.tar.gz" \
    "${BASE_URL}/download/worker-${VERSION}/${LICENSE_ID}" \
    "${VERSION}"

sync_archive \
    master patch \
    "${PKG_DIR}/cryosparc_master_patch.tar.gz" \
    "${BASE_URL}/patch_get/${PATCH_ID}/master" \
    "${VERSION}" \
    "${PATCH_NAME}"

sync_archive \
    worker patch \
    "${PKG_DIR}/cryosparc_worker_patch.tar.gz" \
    "${BASE_URL}/patch_get/${PATCH_ID}/worker" \
    "${VERSION}" \
    "${PATCH_NAME}"
