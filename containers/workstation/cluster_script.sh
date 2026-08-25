#!/bin/bash
#SBATCH --chdir={{ job_dir_abs }}
#SBATCH --job-name cryosparc_{{ project_uid }}_{{ job_uid }}
#SBATCH --gres=gpu:{{ num_gpu }}
#SBATCH --comment="created by {{ job_creator }}"
#SBATCH --partition NV_4090D

license_file="${HOME}/.cryosparc/license_id"
if [[ ! -r "${license_file}" ]]; then
    printf 'CryoSPARC license file is not readable: %s\n' "${license_file}" >&2
    exit 1
fi

export CRYOSPARC_LICENSE_ID="$(<"${license_file}")"
if [[ -z "${CRYOSPARC_LICENSE_ID}" ]]; then
    printf 'CryoSPARC license file is empty: %s\n' "${license_file}" >&2
    exit 1
fi

{{ run_cmd }}
