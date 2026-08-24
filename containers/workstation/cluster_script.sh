#!/bin/bash
#SBATCH --chdir={{ job_dir_abs }}
#SBATCH --job-name cryosparc_{{ project_uid }}_{{ job_uid }}
#SBATCH --gres=gpu:{{ 1 }}
#SBATCH --comment="created by {{ job_creator }}"
#SBATCH --partition NV_4090D


{{ run_cmd }}
