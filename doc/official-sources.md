# 官方来源登记

本文件集中登记研究中实际使用的官方网页，便于部门 MkDocs 统一引用和后续复核。
网页引用按 2026-09-02 核验；CryoSPARC 页面支持在原 URL 末尾追加 `.md` 获取 Markdown 版本。

## CryoSPARC 官方资料

| 编号 | 来源 | 本文档使用的内容 |
| --- | --- | --- |
| CS-001 | [CryoSPARC Installation Prerequisites](https://guide.cryosparc.com/setup-configuration-and-management/cryosparc-installation-prerequisites) | v5.0+ NVIDIA driver `570.26+`、bundled CUDA 12.8、非 root Unix 用户和相同 numeric UID、passwordless SSH、连续端口、shared filesystem、symlink 和 license/update 的 outbound HTTPS。 |
| CS-002 | [Downloading and Installing CryoSPARC](https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/downloading-and-installing-cryosparc) | master/worker package 下载和解包、standalone 命令、master-only 命令、worker `cryosparcw connect`、`cryosparcm cluster connect`、安装目录限制和至少 15GB 空间。 |
| CS-003 | [Environment Variables (v5.0+)](https://guide.cryosparc.com/setup-configuration-and-management/management-and-monitoring-v5.0/environment-variables-v5.0) | `config.sh` 中 master/worker 环境变量的作用域、默认值以及修改 master 配置后需要 `cryosparcm restart`、修改 worker 配置不需要 restart 的规则。 |
| CS-004 | [CryoSPARC Cluster Integration Script Examples](https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/cryosparc-cluster-integration-script-examples) | `cluster_info.json` 必需字段、SLURM `sbatch/squeue/scancel/sinfo` 模板、`cluster_script.sh` 的 Jinja 变量、GPU GRES/cgroup 职责和 `cryosparcm cluster connect` 注册行为。 |
| CS-005 | [Accessing CryoSPARC User Interface](https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/accessing-cryosparc) | base port、Web UI、SSH local port forwarding、反向代理、license server 和 `REQUESTS_CA_BUNDLE`。 |
| CS-006 | [CryoSPARC v5.0 Release Notes](https://cryosparc.com/updates/v5.0) | v5.0 系统和依赖变化的补充背景；版本事实仍以当前 package metadata 和对应安装页面为准。 |

## 调度器和容器引擎官方资料

这些页面不是 CryoSPARC 产品文档，而是用来解释 GridView 外层调度和容器运行语义的上游资料。

| 编号 | 来源 | 本文档使用的内容 |
| --- | --- | --- |
| SL-001 | [Slurm Generic Resource (GRES) Scheduling](https://slurm.schedmd.com/gres.html) | `--gres`/`--gpus` 请求、GPU GRES 分配、`CUDA_VISIBLE_DEVICES`、Prolog/Epilog 和 GPU 编号映射。 |
| SL-002 | [Slurm Control Group in Slurm](https://slurm.schedmd.com/cgroups.html) | `task/cgroup` 对 cpuset、memory 和 GRES/GPU 的约束，以及 cgroup v1/v2 的边界。 |
| CT-001 | [Podman build](https://docs.podman.io/en/latest/markdown/podman-build.1.html) | build context、Dockerfile/Containerfile、`--build-arg` 不自动成为最终 image ENV、build-time `--add-host`/网络行为。 |
| CT-002 | [Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html) | image 默认入口与运行时覆盖、`--entrypoint`、`--env`、`--mount`、`--device`、`/etc/hosts` 和 rootless 运行边界。 |
| CT-003 | [Docker container run](https://docs.docker.com/reference/cli/docker/container/run/) | GridView 使用 Docker/nvidia-docker 时的 `--entrypoint`、`--env`、bind mount、port、device、GPU 和 detached container 语义。 |

## 引用原则

- 官方网页用于确认 CryoSPARC 产品要求和通用容器/调度器语义，不替代本仓库的实现证据。
- 当前仓库脚本、Dockerfile、package archive 和运行日志使用 `direct-source` 或 `runtime-observation` 标注，并保留文件路径和行号。
- 官方安装页仍存在旧段落写 worker driver `520.61.05` 的版本措辞；本项目当前 v5.0+ 结论采用 CS-001 的 `570.26+`，并在 [CryoSPARC 生命周期报告](research/cryosparc-install/README.md) 中明确记录冲突。
- GridView 平台脚本位于远端环境，不属于本仓库；GridView 结论只对已取证的 h1 实例和 job `787683` 负责，不外推为所有平台版本的默认行为。
