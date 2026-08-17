# CryoSPARC Workstation Container

This repository contains the workstation container build and runtime control
script for CryoSPARC v5.0.6.

## What It Provides

- CryoSPARC master and worker in one container.
- Embedded MongoDB runtime managed by CryoSPARC.
- No pre-initialized database or user in the final image.
- Persistent runtime data under `~/.cryosparc`.
- HTTP Web service on base port `61000`.
- Optional GPU registration at runtime.
- Rootless Podman support with `--userns=keep-id`.

The final image still contains the CryoSPARC MongoDB executable. The runtime
database is created by `init`; removing the database software would prevent the
master service from running.

## Build

The four CryoSPARC package archives must be present in `pkg/` locally. They are
licensed distribution artifacts and should not be published without approval.

```bash
export CRYOSPARC_BUILD_LICENSE_ID=00000000-0000-0000-0000-000000000000
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

```bash
cryosparc-workstation init
cryosparc-workstation start
cryosparc-workstation status
cryosparc-workstation stop
cryosparc-workstation restart
cryosparc-workstation reset user
cryosparc-workstation reset data
cryosparc-workstation reset all
```

- `init` creates the runtime database and first admin user. Defaults are email `hpc@szbl.ac.cn`, name `Cryo Sparc`, username `hpc`, and password `SZBL2026`. Interactive prompts show each default in an editable input buffer; press Enter to accept it, or edit it with readline before submitting.
- `start` skips with `already started` when the Web service is already listening.
- `status` reports CryoSPARC process state, Web port, listening address, and container URL.
- `stop` stops CryoSPARC services but leaves the container available for a later `start`.
- `reset user` overwrites only the first user with the init defaults.
- `reset data` removes the database, projects, and scratch data while preserving license configuration.
- `reset all` removes all runtime data, user configuration, and the saved license.
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
