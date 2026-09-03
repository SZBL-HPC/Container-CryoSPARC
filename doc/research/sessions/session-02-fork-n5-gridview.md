# Session 02：fork、n5 与 GridView

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_02f70f697ffeFPDB8zEDHIjDTg` |
| 标题 | 分析安装脚本与 Docker 镜像制作方案（fork #1） |
| 时间 | 2026-08-05 06:14:22 至 2026-09-01 07:48:00 UTC |
| 规模 | 234 messages，1587 parts，94 text parts |
| 审计状态 | 前段重复安装研究；后段 n5 调查经过独立只读复核。 |

初始目标仍是安装脚本和 workstation 镜像分析，user 锚点为 `prt_fd08f097200163b1MMqAbkGPuu`。2026-09-01 的 n5 请求锚点为 `prt_05be82ec7001EgZDcDEo85hqrz`。

## n5 只读验证

在 gpu14 上以 `/dev/null` SSH 配置连接，目标为 `localhost/cryosparc-hybrid:n5`。未运行服务、未挂载业务目录、未使用 sudo。

- image ID 为 `67114eb657f7e613e82543eb4c72867499c34cbaf13434f8d69fc304d132357a`。
- digest 为 `sha256:5afb2cfee0639eeb11e772503e2185feaa70fa700aebc6f4d2a1bd821e02b884`。
- 平台为 `linux/amd64`，大小约 `14.97 GB`，创建时间为 `2026-09-01T01:11:58Z`。
- inspect 显示 ENTRYPOINT `/usr/local/bin/cryosparc-container`、`Cmd=null`、`Volumes=null`，暴露 `22` 和 `61000-61006`。
- n5 的 `cryosparc-container` 实际调用 `/usr/local/bin/cryosparc-workstation`；n5 存在该文件，但不存在 `/usr/local/bin/cryosparc`。
- n5 history 有 COPY `/usr/local/bin/cryosparc-workstation`，没有 COPY `/usr/local/bin/cryosparc`，因此不是当前 `containers/cryosparc5/Dockerfile:127-156` 期望的同一构建结果。
- h1/latest 是较新的另一镜像，包含 `/usr/local/bin/cryosparc`，不能用来替代 n5。

隔离探针使用 `--network none`、`--cap-drop=ALL`、`--security-opt=no-new-privileges`、`--read-only` 和临时 `/tmp`，只执行 `test`。关键输出为：

```text
test mode: no services, data, or license configuration will be changed
```

这证明 test 路径不会启动真实服务或写入业务 runtime；它不证明 n5 的默认无参数入口安全，也不证明 n5 是当前源码重新构建的镜像。

## h1 与 GridView 作业记录

后续专题记录在 `doc/gridview-progress.md:157-198,200-276` 中补齐了 h1 容器和已有作业 `787683` 的宿主侧参数：

- h1 内 `/usr/local/bin/cryosparc` 的 SHA-256 与当前工作区及 commit `8f8671509ca87860a889f5f0eaec266793aac4bc` 一致。
- h1 中观察到 supervisord、MongoDB、Redis、API、command、Web 等进程，但 PID 1 是 `/usr/sbin/sshd -D`。
- `787683_gn02` 记录 `DC_ENTRYPOINT=" --entrypoint /bin/sh "`；`DC_CMD_ARG` 以 runtime setup 开头并以 `/usr/sbin/sshd` 结束。
- `prolog.env.787683.gn02` 的 GPU命令以 `NV_GPU=0 timeout 90m nvidia-docker run` 开头，包含 `--hostname=worker-0`、shared hosts、NVIDIA/Slurm mounts、`--entrypoint /bin/sh` 和 h1 镜像。
- 最终 command 没有调用 `/usr/local/bin/cryosparc-container`、`/usr/local/bin/cryosparc-workstation` 或 `/usr/local/bin/cryosparc`。

因此 GridView 的实际容器创建参数已经从该已有作业的宿主侧文件中确认，但该命令本身只证明 sshd 容器启动，不能证明 CryoSPARC 服务由该次 `docker run` 启动。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_fd08f097200163b1MMqAbkGPuu` | user，2026-08-05 | fork 的原始安装和镜像目标。 |
| `prt_05be82ec7001EgZDcDEo85hqrz` | user，2026-09-01 | 要求在 gpu14 使用 n5 继续 GridView 调查。 |
| `prt_05be8c36e001TqeBDMGMm5Qrs1` | assistant，2026-09-01 | n5 存在性、隔离容器和失败命令阶段总结。 |
| `prt_05beacf47001EgnUwJwPktOnZb` | assistant，2026-09-01 | SSH config 错误和直接连接处理。 |
| `prt_05bec7a5b001B2DOKcuD63Wyv2` | assistant，2026-09-01 | n5 inspect、PID 和运行配置调查。 |
| `prt_05bf0ee8a001yhrx14enltkVMv` | assistant，2026-09-01 | n5 只读调查阶段总结。 |

## 完整性与未决事项

- `session-record` 足以确认调查目标和关键决策；大型远端输出不在 SQLite text part 中逐字复制。
- `runtime-observation` 已确认 n5 metadata 和已有 job `787683` 的 runtime command。
- `unresolved`：n5 的原始 build/push provenance 不在 inspect/history 中，不能从 image ID 反推 registry push 来源。
- `unresolved`：h1 运行中的 CryoSPARC 服务可能由此前的容器生命周期或平台外部流程启动，当前记录不能确定进程的启动者。
- `unresolved`：没有执行真实 n5 `init/start`，因此不对其服务行为、数据目录或 license 处理作运行结论。
