# CryoSPARC Workstation Container

This repository contains the workstation container build and runtime control
script for CryoSPARC v5.0.6.

## What It Provides

- CryoSPARC master and worker in one container.
- Embedded MongoDB runtime managed by CryoSPARC.
- No pre-initialized database or user in the final image.
- Persistent runtime state under `~/.cryosparc`; worker scratch defaults to `/ssd`.
- HTTP Web service on base port `61000`.
- Optional GPU registration at runtime.
- Rootless Podman support with `--userns=keep-id`.
- `cryosparcm` and `cryosparcw` are available in `/usr/local/bin`.
- The master and worker trees are writable by the runtime user for in-container upgrades; `/ssd` is a `777` mount point for optional SSD storage.
- The local Docker worker and the `szbl-cluster` Slurm target are registered together by default.

The final image still contains the CryoSPARC MongoDB executable. The runtime
database is created by `init`; removing the database software would prevent the
master service from running.

## Build

The four CryoSPARC package archives must be present in `pkg/` locally. They are
licensed distribution artifacts and should not be published without approval.

```bash
export CRYOSPARC_BUILD_LICENSE_ID=00000000-0000-0000-0000-000000000000
export CRYOSPARC_CLUSTER_HOSTS='12.12.4.3 login03 login03.szbl.hpc etcd_node'
export CRYOSPARC_WORKER_NOGPU=true
./build-workstation-podman.sh
```

The build license above is only a placeholder. Use a real license through the
environment when building locally, and never commit it.

## Run

Example rootless Podman invocation:

```bash
mkdir -p "$HOME/.cryosparc"
podman run -d \
  --name cryosparc-workstation \
  --hostname worker-0 \
  --userns=keep-id \
  -e HOME="$HOME" \
  -e CRYOSPARC_LICENSE_ID="$CRYOSPARC_LICENSE_ID" \
  -v "$HOME/.cryosparc:$HOME/.cryosparc:Z" \
  -p 40002:22 \
  -p 61000:61000 \
  localhost/cryosparc-workstation:latest
```

With no command arguments, the entrypoint performs `init`, `start`, and
`status`, then keeps the container alive independently of the SSH session.

## Service Commands

The management command is `/usr/local/bin/cryosparc-workstation`. The container
entrypoint is `/usr/local/bin/cryosparc-container`; it starts `sshd` as a daemon,
keeps only the container alive, and leaves CryoSPARC services under supervisord.
The image also provides `/usr/local/bin/cryosparc-download-data`, backed by
`aria2c`.

```bash
cryosparc-workstation init
cryosparc-workstation start
cryosparc-workstation status
eval "$(cryosparc-workstation env)"
cryosparc-workstation shell
cryosparc-workstation stop
cryosparc-workstation restart
cryosparc-workstation reset user
cryosparc-workstation reset data
cryosparc-workstation reset all
cryosparc-download-data --dataset 10025
cryosparc-download-data --dataset PERFORMANCE_BENCHMARK_DATA --output-dir /ssd
```

- `init` creates the runtime database and first admin user. Defaults are email `hpc@szbl.ac.cn`, name `Cryo Sparc`, username `hpc`, and password `SZBL2026`. Interactive prompts show each default in an editable input buffer; press Enter to accept it, or edit it with readline before submitting.
- `start` skips with `already started` when the Web service is already listening.
- `status` reports CryoSPARC process state, Web port, listening address, and container URL.
- `env` prints runtime exports for direct `cryosparcm`/`cryosparcw` commands; activate them with `eval "$(cryosparc-workstation env)"`.
- `shell` opens an interactive shell with the CryoSPARC runtime environment already loaded; type `exit` to return.
- `/usr/local/bin/cryosparcm` automatically loads the same workstation environment before invoking the master CLI.
- The container intentionally sets `CRYOSPARC_FORCE_USER=true` because `/opt/cryosparc` is root-owned in the image while services run as the mapped runtime user. A normal non-container installation should keep the documented default `false` unless an owner check must be bypassed.
- `stop` stops CryoSPARC services but leaves the container available for a later `start`.
- Automatic worker registration uses `--ssdpath /ssd --ssdreserve 768` (MB). Set `CRYOSPARC_SCRATCH_PATH` to override the scratch path and `CRYOSPARC_SSD_RESERVE` to override the SSD reservation.
- Cluster configuration uses the fixed files `/opt/cryosparc/cryosparc_master/bin/cluster_info.json` and `/opt/cryosparc/cryosparc_master/bin/cluster_script.sh`; set `CRYOSPARC_CLUSTER_ENABLED=false` to disable automatic Slurm registration.
- The Slurm template requests at least one GPU through `--gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}`; the `NV_4090D` partition supplies its configured CPU and memory per GPU defaults. CryoSPARC v5 supports both GPU and Multi-GPU job types, so a multi-GPU request remains dynamic while CPU-only jobs are promoted to one GPU on this cluster lane.
- `env` follows the documented v5 environment model in the [CryoSPARC environment variable reference](https://guide.cryosparc.com/setup-configuration-and-management/management-and-monitoring-v5.0/environment-variables-v5.0): it loads the runtime `config.sh` values and sets `CRYOSPARC_FORCE_HOSTNAME=true` for the container hostname mismatch. It does not set `CRYOSPARC_FORCE_USER`; that override remains opt-in.
- The Dockerfile `ARG CRYOSPARC_CLUSTER_HOSTS` adds `12.12.4.3 login03 login03.szbl.hpc etcd_node` to `/etc/hosts` by default; set the same environment variable before `build-workstation-podman.sh` to override it.
- `reset user` overwrites only the first user with the init defaults.
- `reset data` removes the database and projects, and attempts to clean the contents of the scratch directory while preserving the directory itself and the license configuration. Entries without sufficient permissions are skipped.
- `reset all` removes all runtime data, user configuration, and the saved license, and applies the same permission-tolerant scratch cleanup without removing the scratch directory itself.
- `init`, `start`, and `restart` asynchronously scan the entire master installation directory and warm files readable by the runtime user to reduce mechanical-disk startup latency. Unreadable files are skipped and counted. Set `CRYOSPARC_WARM_MASTER_FILES=false` to disable this behavior.

Destructive reset commands require a terminal confirmation. For automation,
set `CRYOSPARC_ASSUME_YES=true`.

Successful `init` and `reset user` commands print the email, username, first
name, last name, and password. Successful `init` also prints a final login
summary containing the email and password. This is intentional for the demo workflow; do not use the demo
passwords in production.

## SSH

The image installs an SSH drop-in at
`/etc/ssh/sshd_config.d/10-cryosparc.conf`:

```text
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
```

SSH is therefore key-based. The CryoSPARC Web password is separate from SSH
authentication.

## License

Never commit a real `CRYOSPARC_LICENSE_ID`. Use the environment or the zero UUID
placeholder shown in the build example.
