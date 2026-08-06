#!/usr/bin/env bash

set -Eeuo pipefail

# The platform may inject an unavailable locale such as en_US.UTF-8 into the
# SSH environment. Redis refuses to start with that locale, so normalize the
# service environment to the locale guaranteed by glibc.
export LANG="${CRYOSPARC_LANG:-en_US.UTF-8}"
export LC_ALL="${CRYOSPARC_LOCALE:-en_US.UTF-8}"

INSTALL_ROOT="${CRYOSPARC_INSTALL_ROOT:-/opt/cryosparc}"
MASTER_ROOT="${INSTALL_ROOT}/cryosparc_master"
WORKER_ROOT="${INSTALL_ROOT}/cryosparc_worker"
INITIAL_DB="${INSTALL_ROOT}/initial/cryosparc_database"

: "${HOME:?HOME must be set}"

CRYOSPARC_HOME="${CRYOSPARC_HOME:-${HOME}/.cryosparc}"
DB_PATH="${CRYOSPARC_HOME}/cryosparc_database"
SCRATCH_PATH="${CRYOSPARC_HOME}/scratch"
PROJECTS_PATH="${HOME}/cryosparc_projects"
LICENSE_FILE="${CRYOSPARC_HOME}/license_id"
MASTER_CONFIG_DIR="${CRYOSPARC_HOME}/master"
WORKER_CONFIG_DIR="${CRYOSPARC_HOME}/worker"

requested_license="${CRYOSPARC_LICENSE_ID:-}"
requested_hostname="${CRYOSPARC_MASTER_HOSTNAME:-}"
requested_base_port="${CRYOSPARC_BASE_PORT:-}"

source "${MASTER_ROOT}/config.sh"

BASE_PORT="${requested_base_port:-${CRYOSPARC_BASE_PORT:-61000}}"

detect_hostname() {
    local hostname_value
    hostname_value="$(hostname -f 2>/dev/null || true)"
    if [[ -z "${hostname_value}" ]]; then
        hostname_value="$(hostname)"
    fi
    printf '%s' "${hostname_value}"
}

MASTER_HOSTNAME="${requested_hostname:-$(detect_hostname)}"
WORKER_NAME="${CRYOSPARC_WORKER_NAME:-${MASTER_HOSTNAME}}"
current_user="$(id -un 2>/dev/null || true)"
SSH_USER="${CRYOSPARC_SSH_USER:-${current_user:-$(id -u)}}"
SSH_STRING="${CRYOSPARC_SSHSTR:-${SSH_USER}@${WORKER_NAME}}"
export USER="${USER:-${SSH_USER}}"

mkdir -p \
    "${DB_PATH}" \
    "${SCRATCH_PATH}" \
    "${PROJECTS_PATH}" \
    "${MASTER_CONFIG_DIR}" \
    "${WORKER_CONFIG_DIR}"

if [[ -s "${LICENSE_FILE}" ]]; then
    LICENSE_ID="$(tr -d '[:space:]' < "${LICENSE_FILE}")"
elif [[ -n "${requested_license}" ]]; then
    LICENSE_ID="${requested_license}"
elif [[ -t 0 ]]; then
    read -r -p 'CryoSPARC license ID: ' LICENSE_ID
else
    printf 'No CryoSPARC license found. Run with a terminal or set CRYOSPARC_LICENSE_ID.\n' >&2
    exit 1
fi

if [[ ! "${LICENSE_ID}" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]]; then
    printf 'Invalid CryoSPARC license ID.\n' >&2
    exit 1
fi

if [[ ! -s "${LICENSE_FILE}" ]]; then
    (umask 077; printf '%s\n' "${LICENSE_ID}" > "${LICENSE_FILE}")
fi

if [[ -z "$(find "${DB_PATH}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    if [[ ! -d "${INITIAL_DB}" ]] || [[ -z "$(find "${INITIAL_DB}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        printf 'Initial CryoSPARC database is missing or empty: %s\n' "${INITIAL_DB}" >&2
        exit 1
    fi
    cp -a "${INITIAL_DB}/." "${DB_PATH}/"
fi

set_config_value() {
    local config_file="$1"
    local config_key="$2"
    local config_value="$3"
    local quoted_value
    local temporary_file

    printf -v quoted_value '%q' "${config_value}"
    temporary_file="$(mktemp "${config_file}.XXXXXX")"
    awk -v key="${config_key}" -v value="${quoted_value}" '
        index($0, "export " key "=") == 1 {
            print "export " key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (!found) print "export " key "=" value
        }
    ' "${config_file}" > "${temporary_file}"
    mv "${temporary_file}" "${config_file}"
}

if [[ ! -f "${MASTER_CONFIG_DIR}/config.sh" ]]; then
    cp "${MASTER_ROOT}/config.sh" "${MASTER_CONFIG_DIR}/config.sh"
fi

set_config_value "${MASTER_CONFIG_DIR}/config.sh" CRYOSPARC_LICENSE_ID "${LICENSE_ID}"
set_config_value "${MASTER_CONFIG_DIR}/config.sh" CRYOSPARC_MASTER_HOSTNAME "${MASTER_HOSTNAME}"
set_config_value "${MASTER_CONFIG_DIR}/config.sh" CRYOSPARC_BASE_PORT "${BASE_PORT}"
set_config_value "${MASTER_CONFIG_DIR}/config.sh" CRYOSPARC_DB_PATH "${DB_PATH}"

printf 'export CRYOSPARC_LICENSE_ID=%q\n' "${LICENSE_ID}" > "${WORKER_CONFIG_DIR}/config.sh"

export CRYOSPARC_CONFIG_DIR="${MASTER_CONFIG_DIR}"
export CRYOSPARC_LOG_DIR="${MASTER_CONFIG_DIR}/run"
export CRYOSPARC_FORCE_USER=true
export CRYOSPARC_FORCE_HOSTNAME=true

if [[ "${CRYOSPARC_START_SSHD:-true}" == "true" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
        mkdir -p /run/sshd
        ssh-keygen -A
        if ! ss -ltnH 'sport = :22' | grep -q .; then
            /usr/sbin/sshd
        fi
    elif ! ss -ltnH 'sport = :22' | grep -q .; then
        printf 'sshd is not running and run.sh is not running as root\n' >&2
        exit 1
    fi
fi

start_master() {
    local attempt

    for attempt in 1 2 3; do
        if "${MASTER_ROOT}/bin/cryosparcm" start; then
            return 0
        fi
        printf 'CryoSPARC master is not ready; retrying (%s/3)\n' "${attempt}" >&2
        sleep 5
    done

    return 1
}

start_master

wait_for_api() {
    local api_port=$((BASE_PORT + 2))
    local attempt

    for attempt in {1..30}; do
        if curl --noproxy '*' --fail --silent --show-error --max-time 5 \
            -H "License-ID: ${LICENSE_ID}" \
            "http://127.0.0.1:${api_port}/" >/dev/null; then
            return 0
        fi
        sleep 2
    done

    printf 'CryoSPARC API did not become ready on port %s\n' "${api_port}" >&2
    return 1
}

wait_for_api

start_application_services() {
    local service

    # A failed full start can leave the supervisor and API running while the
    # remaining application services are still stopped.
    for service in scheduler command_vis app app_api; do
        "${MASTER_ROOT}/bin/cryosparcm" start "${service}"
    done
}

start_application_services

export CRYOSPARC_CONFIG_DIR="${WORKER_CONFIG_DIR}"
export CRYOSPARC_LOG_DIR="${WORKER_CONFIG_DIR}/run"

GPU_ARGS=()
if [[ "${CRYOSPARC_NOGPU:-false}" == "true" ]] \
    || ! command -v nvidia-smi >/dev/null 2>&1 \
    || ! nvidia-smi -L >/dev/null 2>&1; then
    GPU_ARGS+=(--nogpu)
fi

"${WORKER_ROOT}/bin/cryosparcw" connect \
    --license "${LICENSE_ID}" \
    --master "${MASTER_HOSTNAME}" \
    --port "${BASE_PORT}" \
    --worker "${WORKER_NAME}" \
    --sshstr "${SSH_STRING}" \
    --ssdpath "${SCRATCH_PATH}" \
    "${GPU_ARGS[@]}"

SUPERVISOR_PID_FILE="${MASTER_CONFIG_DIR}/run/supervisord.pid"
for _ in {1..30}; do
    [[ -s "${SUPERVISOR_PID_FILE}" ]] && break
    sleep 1
done

if [[ ! -s "${SUPERVISOR_PID_FILE}" ]]; then
    printf 'CryoSPARC supervisor PID file was not created: %s\n' "${SUPERVISOR_PID_FILE}" >&2
    exit 1
fi

read -r SUPERVISOR_PID < "${SUPERVISOR_PID_FILE}"

cleanup() {
    "${MASTER_ROOT}/bin/cryosparcm" stop >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

while kill -0 "${SUPERVISOR_PID}" 2>/dev/null; do
    sleep 5
done

printf 'CryoSPARC supervisor exited: %s\n' "${SUPERVISOR_PID}" >&2
exit 1
