# 已核实事实

本文件只列出有直接源码、已保存 runtime 输出或可复查 session 锚点支持的事实。事实可能只适用于注明的版本、镜像或测试环境。

## 构建与运行时

| ID | 事实 | 来源 |
| --- | --- | --- |
| F-001 | 当前 Dockerfile 固定 `linux/amd64`，基础镜像为 CUDA 12.8.2/Ubuntu 24.04。 | `containers/cryosparc5/Dockerfile:5-9` |
| F-002 | 当前 image target 为 `master`、`workstation`、`hybrid`；`master0` 提供公共 master 层。 | `containers/cryosparc5/Dockerfile:127-171`；`README.md:8-10` |
| F-003 | 最终镜像不预初始化业务数据库或用户；runtime state 依赖 `~/.cryosparc` 和外部挂载。 | `README.md:11-18,75-94`；`containers/cryosparc5/Dockerfile:116-125` |
| F-004 | entrypoint 启动 sshd、调用 `/usr/local/bin/cryosparc`，随后用 sleep 保持容器存活。 | `containers/cryosparc5/entrypoint:5-35` |
| F-005 | 当前 wrapper 的 core service 顺序包括 master、API readiness、scheduler、command、app 和 app_api，并等待 Web。 | `containers/cryosparc5/cryosparc:554-564`；`install-analysis.md:412-450` |
| F-006 | 本地 worker 默认以 `localhost` 语义注册；无 GPU 或 GPU 查询失败时 connect 追加 `--no-gpu`。 | `containers/cryosparc5/cryosparc:511-539`；`cluster-adaptation.md:130-155` |

## 安装与版本

| ID | 事实 | 来源 |
| --- | --- | --- |
| F-007 | 产品安装方式归纳为 standalone workstation 与分离 master/worker 两类；cluster 是后续 scheduler integration。 | `install-analysis.md:12-18,80-229` |
| F-008 | 当前 package 核验为 master/worker `v5.0.7`、revision `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`；历史 `install-analysis.md` 主要对应 v5.0.6/patch 260710。 | `doc/cryosparc-lifecycle-progress.md:17-19,223-230`；`install-analysis.md:19-27` |
| F-009 | 构建阶段使用零 UUID placeholder，真实 license 在 runtime 从环境或 `~/.cryosparc/license_id` 提供。 | `containers/cryosparc5/Dockerfile:61-84`；`containers/cryosparc5/cryosparc:282-307` |
| F-010 | worker install 的 `--nogpu` 与 connect 的 `--no-gpu` 是两个不同开关。 | `install-analysis.md:362-410` |

## 网络与 Slurm

| ID | 事实 | 来源 |
| --- | --- | --- |
| F-011 | 有 cluster files 时 wrapper 从默认路由 source IPv4 选择 master 地址；显式纯 IPv4 可覆盖自动选择。 | `containers/cryosparc5/cryosparc:68-138`；`cluster-adaptation.md:101-128` |
| F-012 | `CRYOSPARC_FORCE_HOSTNAME=true` 只绕过 hostname check，不负责 hostname 到 IP 的转换。 | `cluster-adaptation.md:77-100` |
| F-013 | `cluster_info.json` 的 SSH send command 与作业脚本中的 `--master` 是不同职责。 | `cluster_info.json:2-13`；`cluster-adaptation.md:64-75` |
| F-014 | 当前 Slurm template 至少请求一块 GPU，使用 `NV_4090D`，并从共享 home license file 导出 license。 | `cluster_script.sh:2-20` |
| F-015 | 已记录的一 GPU/两 GPU Slurm smoke 分别产生 `CUDA_VISIBLE_DEVICES=0`/`0,1`，CPU 默认随 GPU 数量变化。 | `live-test.md:152-173` |
| F-016 | stale job 查询曾输出 `slurm_load_jobs error: Invalid job id specified` 并重试 97 次，阻塞后续服务启动。 | `history-audit-progress.md:74-76`；`session-03-cli-runtime-slurm.md` |

## GridView 与实验

| ID | 事实 | 来源 |
| --- | --- | --- |
| F-017 | `localhost/cryosparc-hybrid:n5` 的 ID、digest、平台、ENTRYPOINT 和大小已通过 gpu14 只读 inspect 核验。 | `doc/research/gridview/README.md`；`doc/gridview-progress.md:8-25` |
| F-018 | n5 的 container wrapper 调用 `cryosparc-workstation`，而当前 Dockerfile 期望复制 `cryosparc`；两者不是同一构建结果的充分证据。 | `doc/gridview-progress.md:19-25`；`containers/cryosparc5/Dockerfile:137-139` |
| F-019 | GridView job `787683` 的宿主侧 runtime command 覆盖 ENTRYPOINT 为 `/bin/sh`，最终 command 以 `/usr/sbin/sshd` 结束，未调用 CryoSPARC wrapper。 | `doc/gridview-progress.md:252-264` |
| F-020 | `787683` 的 shared hosts 文件含 `173.0.74.4 worker-0`，但日志仍出现 `sudo: unable to resolve host worker-0: Temporary failure in name resolution`。 | `doc/gridview-progress.md:223-270` |
| F-021 | `/ai-forward/<id>/` prefix 与 CryoSPARC root-absolute Web asset/API/WebSocket 路径不兼容；直接端口/无 prefix 路径的服务资源和协议接口正常。 | `live-test.md:175-218`；`history-audit-progress.md:30-35` |
| F-022 | Podman 当前不支持 `ADD --unpack=true`；多镜像 archive 必须检查 `manifest.json`，旧单 entry archive 不能当成三镜像包。 | `containers/cryosparc5/Dockerfile:47-69`；`session-06-add-archive-transfer.md` |
