#!/bin/bash
#SBATCH --chdir={{ job_dir_abs }}
#SBATCH --job-name cryosparc_{{ project_uid }}_{{ job_uid }}
#SBATCH --gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}
#SBATCH --comment="created by {{ job_creator }}"
#SBATCH --partition NV_4090D

license_file="${HOME}/.cryosparc/license_id"
[[ -r "${license_file}" ]] || {
    printf 'CryoSPARC license file is not readable: %s\n' "${license_file}" >&2
    exit 1
}

export CRYOSPARC_LICENSE_ID="$(<"${license_file}")"
[[ -n "${CRYOSPARC_LICENSE_ID}" ]] || {
    printf 'CryoSPARC license file is empty: %s\n' "${license_file}" >&2
    exit 1
}

{{ run_cmd }}
