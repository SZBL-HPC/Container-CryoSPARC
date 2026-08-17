# Agent Test Environment

This file records the non-secret connection and test conventions used by
agents working on this repository. It is intended for a public repository.

## Local SSH Config

- Config path: `~/git/szbl-hpc/Qbics/new/ssh/config`
- Repository path: `~/git/szbl-hpc/CryoSPARC`
- macOS workspace path used in this checkout: `/Volumes/Develop/git/szbl-hpc/CryoSPARC`
- Private key files are referenced by the SSH config but must never be copied into this repository.
- Known-host files are local machine state and must not be committed.

Use the configured aliases when possible:

```bash
ssh -F "$HOME/git/szbl-hpc/Qbics/new/ssh/config" gpu14
ssh -F "$HOME/git/szbl-hpc/Qbics/new/ssh/config" ln03
```

## Test Machines

| Alias | Hostname/IP | User | Purpose | Workdir |
| --- | --- | --- | --- | --- |
| `gpu14` | `10.68.247.14` | `galaxy` | Podman image builds and GPU smoke tests | `~/git/szbl-hpc/CryoSPARC` |
| `ln03` | `10.68.247.43` | `xshu` | Direct HTTP and network-path tests | N/A |
| `ln01` | `10.68.247.105` | `xshu` | General Linux test host | N/A |
| `docker` | `10.68.247.45:40009` | `xshu` | Legacy cuda-ssh endpoint | N/A |
| `workstation-live` | `10.68.247.45:40002` | `xshu` | Current live workstation endpoint | N/A |

The `workstation-live` endpoint is currently used directly because it is not a
named host in the checked SSH config. Its container IP can change; use the
workstation `status` command or the platform container inspection to obtain the
current address.

## Workstation Ports

- `61000`: CryoSPARC Web service.
- `61001`: embedded MongoDB.
- `61002`: master API readiness endpoint.
- `61003`: command service.
- `61004`: Redis cache.
- `61006`: application API.
- `22`: container SSH daemon.
- `6080`: platform HTTP gateway under test. Its `ai-forward` route adds a URL prefix, which breaks CryoSPARC's root-absolute Web asset and API paths; do not use it for workstation HTTP forwarding. Select the platform's socket forwarding port instead.

The expected startup dependency order is database, Redis, API, scheduler and
application services. `61002` is checked before starting the application
services because user creation and worker registration depend on the API.

## Runtime Workflow

The image management command is `cryosparc-workstation`; the container entrypoint
is `cryosparc-container`. The entrypoint starts `sshd` as a daemon. With no
arguments the management command runs `init`, `start`, and `status`, then
returns. The separate container entrypoint keeps the container alive. The persistent
database, license, logs, scratch data, and project data are outside the image.

```bash
cryosparc-workstation init
cryosparc-workstation status
cryosparc-workstation stop
cryosparc-workstation start
cryosparc-workstation reset user
cryosparc-workstation reset data
cryosparc-workstation reset all
```

The default first-user values are:

- Email: `hpc@szbl.ac.cn`
- Username: `hpc`
- Name: `Cryo Sparc`
- Password: `SZBL2026`

`reset user` always overwrites only the first user with these values. It does
not create a second user.

## Testing Rules

- Do not run `reset data` or `reset all` against a live production container without explicit approval.
- A disposable live test home may be reset when it contains no real projects.
- After a reset test, leave the test container initialized and verify `status` and Web port `61000`.
- A failed first API check can be a normal startup race if the supervisor remains alive and the API becomes ready shortly afterward.
- The container uses HTTP on `61000`; HTTPS requires a separate TLS termination layer.
- GridView HTTP forwarding is not usable through the prefixed `ai-forward` route; use socket forwarding for the workstation port.

## Public Repository Rules

- Never commit a real CryoSPARC license UUID.
- Use `CRYOSPARC_LICENSE_ID` from the environment or a zero UUID placeholder in examples.
- Do not commit private SSH keys, `known_hosts`, local SSH config secrets, or copied package artifacts unless their distribution is explicitly approved.
- `SZBL2026` and `theRootPw2021` are demo-only credentials permitted in these documents; they must not be treated as production secrets.
