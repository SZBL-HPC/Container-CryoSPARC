# GridView 研究进展

记录基于本 session 已完成的源码阅读、图谱查询和只读运行验证。
本次未启动真实 CryoSPARC 服务、未提交 Slurm 作业、未使用 sudo 操作 GridView/Docker，也未提交 Git。

## 当前已完成结果

### gpu14 镜像

- 连接方式使用了 `ssh -F /dev/null -o StrictHostKeyChecking=accept-new galaxy@10.68.247.14`，避开损坏的 SSH config alias。
- `localhost/cryosparc-hybrid:n5` 已确认存在。
- 镜像 ID：`67114eb657f7e613e82543eb4c72867499c34cbaf13434f8d69fc304d132357a`。
- 镜像 digest：`sha256:5afb2cfee0639eeb11e772503e2185feaa70fa700aebc6f4d2a1bd821e02b884`。
- 镜像为 `linux/amd64`，大小约 `14.97 GB`，创建时间为 `2026-09-01T01:11:58Z`。
- `podman image inspect` 确认 `Entrypoint=["/usr/local/bin/cryosparc-container"]`，`Cmd=null`，默认 `User` 和 `WorkingDir` 为空，`Volumes=null`，暴露 22 和 61000-61006 端口。
- 镜像 ENV 包含 `CRYOSPARC_INSTALL_ROOT=/opt/cryosparc`、`CRYOSPARC_BASE_PORT=61000`、`CRYOSPARC_SUPERVISOR_PID_FILE=/var/run/cryosparc-supervisord.pid`、locale、CUDA/NVIDIA 变量；没有发现 GridView 专用 ENV。
- Podman 版本为 `5.4.2`，rootless overlay，`graphroot=/home/galaxy/.local/share/containers/storage`，`runroot=/run/user/1000/containers`。

### n5 实际入口与工作区源码的差异

- n5 内的 `/usr/local/bin/cryosparc-container` 在第 21 行实际调用 `/usr/local/bin/cryosparc-workstation "$@"`，第 24 行的停止逻辑也调用该脚本。
- n5 内存在 `cryosparc-workstation`，但不存在 `/usr/local/bin/cryosparc`。
- n5 history 记录的是 COPY `/usr/local/bin/cryosparc-workstation`，没有 COPY `/usr/local/bin/cryosparc`。
- 当前工作区 `containers/cryosparc5/Dockerfile:137-139` 期望复制 `/usr/local/bin/cryosparc` 和 `/usr/local/bin/cryosparc-container`，因此 n5 不是当前工作区 Dockerfile 的同一构建产物。
- gpu14 上较新的 `localhost/cryosparc-hybrid:h1` 和 `latest` 指向另一镜像，创建时间为 `2026-09-01T01:45:54Z`；其 history 和内容包含 `/usr/local/bin/cryosparc`。本研究没有替换或重打 n5 标签。

### 安全容器验证

使用过以下隔离参数：

```bash
--network none --cap-drop=ALL --security-opt=no-new-privileges
--read-only --tmpfs /tmp:rw,noexec,nosuid,nodev
```

验证默认入口时额外设置 `CRYOSPARC_START_SSHD=false`，并执行：

```bash
podman run --rm --name <isolated-probe> ... \
  -e CRYOSPARC_START_SSHD=false \
  localhost/cryosparc-hybrid:n5 test
```

关键输出：

```text
test mode: no services, data, or license configuration will be changed
```

注入的 `CRYOSPARC_INITIAL_*` 值能够被入口脚本读取。
进程检查只有 `bash /usr/local/bin/cryosparc-container test` 和 `sleep 3600`，没有 sshd、supervisord 或 CryoSPARC 服务。

验证 ENV 消费时，在容器自己的 `/tmp` tmpfs 中创建了零 UUID license 和临时 runtime config，然后执行入口的 `env` 命令。
`CRYOSPARC_BASE_PORT=62099` 输出为 `export CRYOSPARC_BASE_PORT=62099`。
传入纯 IPv4 `CRYOSPARC_MASTER_HOSTNAME=192.0.2.10` 输出为 `export CRYOSPARC_MASTER_HOSTNAME=192.0.2.10`。
传入非 IPv4 的 `gridview-env-master` 时，由于 cluster 文件存在，脚本改用容器默认路由地址并设置 `CRYOSPARC_MASTER_HOSTNAME_AUTO=true`。

镜像和探针均无业务目录挂载。
默认网络的只读探针 inspect 为 `Mounts=[]`，容器内只观察到 Podman 自动生成的 `/etc/resolv.conf`、`/etc/hosts`、`/etc/hostname` tmpfs，以及探针显式创建的 `/tmp`。

### 当前工作区构建逻辑

- `containers/cryosparc5/Dockerfile:5-9` 固定 CUDA 12.8.2、Ubuntu 24.04 和 amd64。
- `containers/cryosparc5/Dockerfile:127-156` 构建 `master0`，设置运行时 ENV、复制 master wrapper、创建 `/ssd`、暴露端口并设置 ENTRYPOINT。
- `containers/cryosparc5/Dockerfile:158-171` 构建 `master`、`workstation` 和 `hybrid` target；hybrid 追加 worker 和 cluster files。
- `build-workstation-podman.sh:132-204` 负责 target、tag、build args 和 `podman build`，不负责 runtime `podman run`、GridView 或 Slurm 启动。
- 镜像没有声明 Docker/Podman VOLUME；runtime persistence 依赖外部挂载，默认情况下状态只在容器 writable layer 中。

### CryoSPARC 自身启动链

- `containers/cryosparc5/entrypoint:5-21,23-35` 默认启动 sshd，随后调用 CryoSPARC wrapper，并以 sleep 循环保持容器存活。
- 当前源码 `containers/cryosparc5/cryosparc:1019-1029` 表明无参数运行顺序为 `init`、`start`、`status`、后台 master 文件预热。
- `containers/cryosparc5/cryosparc:554-564` 的核心服务顺序是解析 master 地址、写 runtime config、创建 DB/scratch/projects、启动 master、等待 61002 API、启动 scheduler/command/app/app_api、等待 61000 Web。
- `containers/cryosparc5/cryosparc:683-751` 的 init 顺序是创建用户、启动核心服务、写 init marker、注册本地 worker、注册 cluster。
- `containers/cryosparc5/cryosparc:511-552` 注册本地 worker；若没有 `nvidia-smi` 或显式 `CRYOSPARC_NOGPU=true`，会追加 `--no-gpu`。
- `containers/cryosparc5/cryosparc:545-552` 在 `CRYOSPARC_CLUSTER_ENABLED=true` 且两个 cluster 文件存在时调用 `cryosparcm cluster connect`。
- `ex/cryosparc_master/core/core.py:50-85` 的 `Core.startup` 连接 MongoDB/GridFS、Redis，并在 master mode 初始化 Athena/webhook client。
- `ex/cryosparc_master/core/instance.py:142-192` 是 instance DB lifecycle，不是 GridView 或容器启动器。

### CryoSPARC Slurm cluster 链

- `containers/cryosparc5/cluster_info.json:2-12` 配置 `ssh 12.12.4.3 {{ command }}`、`sbatch`、`squeue`、`scancel`、`sinfo`，cluster 名为 `szbl-cluster`，cache 为 `/scratch.local`。
- `containers/cryosparc5/cluster_script.sh:2-20` 渲染作业目录、作业名、GPU 数量和 `NV_4090D` 分区，从 `${HOME}/.cryosparc/license_id` 导出 license，最后执行 `{{ run_cmd }}`。
- `ex/cryosparc_master/cli/cluster.py:35-58` 读取并验证两个 cluster 文件，然后调用 `core.cluster.connect`。
- `ex/cryosparc_master/core/cluster.py:23-38` 只在 CryoSPARC 数据库中创建 lane、`SchedulerTarget` 和 Cluster 配置。
- `ex/cryosparc_master/core/jobs.py:694-728` 渲染并写出 submission script，生成 qsub/send 命令，执行 `processing.check_output(..., shell=True, env=cluster.get_cluster_env())`，解析 Slurm job ID 并标记 LAUNCHED。
- 图谱 generation 为 `2026-08-17T02:25:43Z`；`trace_path` 证实 `launch_job -> launch_job_on_cluster`，其关键下游包括 template args、`get_cluster_env`、`processing.check_output` 和 job ID 解析。

### 当前 GridView/Slurm 外层链

已通过只读 SSH 从 `xshu@10.68.247.43` 取得并精读当前可读脚本：

1. `/opt/gridview/slurm/etc/slurm.conf:225` 配置 `Prolog=/opt/gridview/slurm/etc/sothisai/slurm.prolog`；`scontrol show config` 同样返回该值，`PrologFlags=Alloc,Contain`。
2. `/opt/gridview/slurm/etc/sothisai/slurm.prolog:17-19,137-166` 加载 `function.sh`，读取 envprolog 和任务信息，按 `DLFRAMEWORK/task_type` 选择并 source framework prolog。
3. `/opt/gridview/slurm/etc/sothisai/instance/job/prolog:24-45,50-65` 计算 CPU/GPU/内存、准备 framework mounts 和运行时参数，并调用 `sh /opt/gridview/slurm/etc/sothisai/startRoleContainer.sh ...`。
4. `/opt/gridview/slurm/etc/sothisai/instance/job/prolog:43` 构造的 runtime command 会生成 profile、重写 `/etc/ssh/sshd_config`、复制 `/root/.ssh`，最后执行 `/usr/sbin/sshd -D`；没有调用 CryoSPARC wrapper。
5. `/opt/gridview/slurm/etc/sothisai/startRoleContainer.sh:82-85` 在 `DC_ENTRYPOINT` 为空时显式设置 `--entrypoint='/bin/sh'`。
6. `/opt/gridview/slurm/etc/sothisai/startRoleContainer.sh:132-142` GPU 使用 `NV_GPU=... timeout 90m nvidia-docker run`，CPU 使用 `docker run`。
7. `/opt/gridview/slurm/etc/sothisai/startRoleContainer.sh:144-157` 组装 hostname、`-v ${SHARED_HOSTS}:/etc/hosts`、framework mounts、ENV、entrypoint、image 和 command，最后通过 `eval "$docker_run_cmd 2>&1"` 创建容器。
8. `/opt/gridview/slurm/etc/sothisai/startRoleContainer.sh:204-208,237-264` 负责 pull/start 和记录容器 inspect 的 ID、状态、IP、资源、端口和挂载。

因此当前实际外层创建路径是：

```text
Slurm Prolog
  -> slurm.prolog
  -> instance/job/prolog
  -> startRoleContainer.sh
  -> docker run / nvidia-docker run
```

`/usr/bin/ai_docker:1-3` 只是转发到 `/opt/gridview/scripts/scheduler/ai_docker/ai_docker`。
后者 `:14-74` 处理 `ps/exec/start/inspect/logs/stats/top`，`ai_docker_util:2-3,18-28,41-43` 直接调用 `docker $*`。
因此 `ai_docker` 是管理/查看包装器，不是当前容器创建路径。

GridView 的 prolog 默认将容器入口覆盖为 `/bin/sh`，并把最终命令设为 runtime setup 加 `/usr/sbin/sshd -D`。
如果没有额外 runtime command 显式启动 `/usr/local/bin/cryosparc-container` 或 n5 实际的 `/usr/local/bin/cryosparc-workstation`，Dockerfile ENTRYPOINT 不会启动 CryoSPARC master/worker 服务。

## 历史未完成事项与阻塞（补证前）

- 未在 n5 中运行 `init`、`start` 或默认无参数入口，因为这会启动真实服务、创建数据库并可能写入持久化数据；用户明确要求避免该操作。
- 未提交或测试新的 Slurm 作业；用户已说明当前没有空闲计算资源。
- 在本节形成时尚未确认当前某个 live GridView CryoSPARC 作业的最终 `DC_ENTRYPOINT`、`DC_CMD_ARG` 和完整 mounts；后续已对已有作业 `787683` 补充完成该项只读核验，见 `:200-276`。
- `xshu` 直接执行 `docker ps` 无权访问 `/var/run/docker.sock`；非 sudo 执行 `/usr/bin/ai_docker ps` 还因 `/var/log/sothisai_ai_docker.log` 权限不足失败。为遵守最小权限，没有使用 sudo。
- 未确认 `cluster_info.json` 中 `12.12.4.3` 的 SSH 连通性、实际 `sbatch` 接受情况或计算节点到 master 的网络可达性。
- 旧 `containers/cuda-ssh/deployment-check.md` 和 `containers/cryosparc5/cluster-adaptation.md` 提供历史 GridView 运行记录；它们不能替代 `787683` 的实例证据，也不能证明 n5 的 build/push provenance。
- 工作区图谱 generation 早于当前未跟踪 `ex/`/`pkg/` 文件状态；已对引用路径执行 coverage check，结果为 `no_recorded_issue`，但多数容器脚本为 `not_tracked`、源码为 `metadata_changed`，所以仍以直接 source 为准。
- Dockerfile 通过 `ARG CRYOSPARC_CLUSTER_HOSTS` 尝试写入 `/etc/hosts`，但 n5/h1 使用 `--no-hosts` 检查时 `/etc/hosts` 均为 0 bytes；build-time 修改特殊 hosts 文件没有持久化。当前 raw IP `12.12.4.3` 不依赖该 hosts 条目。

## 后续建议（仍适用部分）

1. 仅当 n5 tag 可能变化时重新执行 `podman image inspect localhost/cryosparc-hybrid:n5`；当前已确认 n5 ID，仍不要把 h1/latest 当作 n5 替代品。
2. 如果必须验证服务启动，先明确使用一次性、隔离的 runtime home 和显式 `CRYOSPARC_ASSUME_YES` 策略，并获得用户对启动服务和写入数据的授权；默认入口必须继续覆盖为安全命令，不能直接无参数运行。
3. GridView 实际创建参数已由已有作业 `787683` 只读取证；不要为重复该结论提交额外作业。
4. 该作业的 runtime command 已确认没有显式启动 CryoSPARC wrapper；仍需另找可审计的服务启动记录，不能由 `/usr/sbin/sshd -D` 或当前进程列表反推。
5. 若要修复构建产物一致性，应重新构建并使用明确的新 tag，随后分别核验 `/usr/local/bin/cryosparc`、entrypoint 内容、cluster files、ENV 和无宿主业务挂载；不要覆盖 n5。
6. 若要修复 cluster hosts 设计，应使用 runtime `--add-host`、可靠 DNS 或 GridView 的 shared hosts 配置，不要继续假定 Dockerfile 对 `/etc/hosts` 的 build-time 写入会持久化。
7. 修改 `cluster_info.json` 或 `cluster_script.sh` 后，需要重新执行 `cryosparcm cluster connect`；普通 `start`/`restart` 不会自动重读数据库中的旧模板。

## 仓库状态

本段记录的是本专题文件首次创建阶段的工作区状态；随后历史审计本轮又新增了 `doc/research/` 和 `doc/findings/` 正式报告。
工作区原有用户未跟踪的 `ex/` 和 `pkg/` 内容始终没有被修改、清理或提交。

## Session 终止前补充

- 最终 n5 复核仍返回 image ID `67114eb657f7e613e82543eb4c72867499c34cbaf13434f8d69fc304d132357a`、ENTRYPOINT `/usr/local/bin/cryosparc-container`、`Cmd=null`、`Volumes=null`。
- 最终安全 `test` 探针仍只输出 `test mode: no services, data, or license configuration will be changed`；使用 `timeout` 结束入口的保持存活循环，退出属于预期行为。
- `podman ps -a --filter name=cryosparc-hybrid-gridview` 最终无输出，已退出的隔离探针已清理；未触碰宿主其他容器。
- 最终本地 `git status --short --untracked-files=no` 无输出，说明没有产生 tracked 文件修改；此前用户已有的未跟踪 `ex/`、`pkg/` 仍未处理。
- 本补充不改变前文结论：n5 实际入口调用 `cryosparc-workstation`，而当前工作区源码期望 `/usr/local/bin/cryosparc`；GridView 外层创建路径仍为 Slurm Prolog -> `slurm.prolog` -> instance prolog -> `startRoleContainer.sh` -> `docker run`/`nvidia-docker run`，`ai_docker` 仍仅是管理包装器。

## 补充

现在可以用 `ssh -p 40005 xshu@10.68.247.45` 访问最新的 `cryosparc-hybrid:h1` 的容器实例。其中额外包含了scp覆盖的commit 8f8671509ca87860a889f5f0eaec266793aac4bc。

## 2026-09-02 h1 容器只读调查

本次选择的单个有界任务是：只读检查 `ssh -p 40005 xshu@10.68.247.45` 当前实例的实际 PID 1、运行进程、入口脚本、运行时 ENV 和挂载。
没有运行 `init`、`start`、默认无参数入口或任何 Slurm 命令，没有使用 `sudo`，没有写入容器或宿主数据。

### 连接阻塞与处理

- 初始命令 `ssh -p 40005 -o BatchMode=yes -o ConnectTimeout=10 xshu@10.68.247.45 true` 报告本机 `known_hosts:363` 的主机密钥冲突；远端 ED25519 指纹为 `SHA256:EQgohgXZwu76vZ3mS4HfB9lRpVpewz1cS6MyYopnhB0`。
- 为不修改本机 `known_hosts`，后续只读命令统一使用 `-F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`；`id` 成功返回 `uid=5060(xshu) gid=1111(hpc_core)`。
- 远端每次命令前还会打印 `error: could not lock config file /lenovofs1/home/xshu/.gitconfig: File exists` 和 `fatal: not in a git directory`。
  这些是远端登录环境噪声，未修改其配置；相关路径不能作为本次调查的可写工作区。

### 实际进程与入口

- 命令 `ssh ... 'ps -p 1 -o pid=,ppid=,args='` 和 `ssh ... 'tr "\\000" "\\n" </proc/1/cmdline'` 的结果均为：`PID 1, PPID 0, sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups`。
- 命令 `ssh ... 'ps -eo pid=,ppid=,args='` 还观察到 `supervisord` PID `119257`（PPID `1`），以及其子进程 `mongod --auth ... --port 61001`、`redis-server *:61004`、三类 `uvicorn` API 进程、`flask ... -p 61003`、`dist/server/index.js` 和 `bundle/main.js`。
  因此该 h1 实例当前确实有 CryoSPARC master/Web 进程，但容器 PID 1 不是 CryoSPARC wrapper；这与“GridView 覆盖入口后由 `/usr/sbin/sshd -D` 作为最终命令”一致。
- h1 内 `/usr/local/bin/cryosparc-container:1-35` 仍是当前工作区式入口：`:5-20` 定义并启动 sshd，`:21` 调 `/usr/local/bin/cryosparc "$@"`，`:23-35` 捕获信号并以 `sleep 3600` 保持容器存活。
  但 PID 1 为 sshd，不能据此证明这次容器创建时实际执行了该入口脚本。
- h1 内 `/usr/local/bin/cryosparc:545-552` 的 `connect_cluster()` 在 cluster 文件存在且 `CRYOSPARC_CLUSTER_ENABLED` 未显式设为 false 时调用 `cryosparcm cluster connect`；`:753-776` 的 `start_command()` 在 `start_core_services`、`reset_non_cluster_resources`、`connect_worker` 后于第 `773` 行调用 `connect_cluster()`。

### h1 脚本部署核对

- 命令 `shasum -a 256 containers/cryosparc5/cryosparc`、命令 `git show 8f8671509ca87860a889f5f0eaec266793aac4bc:containers/cryosparc5/cryosparc | shasum -a 256` 和远端命令 `ssh ... 'sha256sum /usr/local/bin/cryosparc'` 三者均为 `3c15b19892dad8c4c8e000c77f767a2de3e630c559edf70a68bbb7acea30a2f0`。
  这证明 h1 容器内 `/usr/local/bin/cryosparc` 与 commit `8f8671509ca87860a889f5f0eaec266793aac4bc` 的工作区脚本内容完全一致。
- 该 commit 的唯一变更是 `containers/cryosparc5/cryosparc:773` 的 `connect_cluster` 调用，commit 标题为 `Add connect_cluster() to start_command()`。
- 远端 `/usr/local/bin/cryosparc-container` 的 SHA-256 为 `86abacdaf0ed4d68d8877756ea5fe7b60f15e6bc8536388b70636b0f1633b505`；本次没有用它替换或重启入口。

### ENV 与挂载证据

- 命令 `ssh ... 'printenv DC_ENTRYPOINT || printf "<unset>\\n"'` 和同样方式读取 `DC_CMD_ARG` 均返回 `<unset>`。
- 对现有 `supervisord` 的 `/proc/119257/environ` 只筛选非敏感变量，命令为 `ssh ... 'tr "\\000" "\\n" </proc/119257/environ | grep -E "^(CRYOSPARC_BASE_PORT|CRYOSPARC_INSTALL_ROOT|CRYOSPARC_MASTER_HOSTNAME|CRYOSPARC_CLUSTER_ENABLED|CRYOSPARC_START_SSHD|DC_ENTRYPOINT|DC_CMD_ARG)="'`；结果为 `CRYOSPARC_MASTER_HOSTNAME=173.0.74.4`、`CRYOSPARC_INSTALL_ROOT=/opt/cryosparc`、`CRYOSPARC_BASE_PORT=61000`，没有 `DC_ENTRYPOINT` 或 `DC_CMD_ARG`。
- 命令 `ssh ... 'findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS'` 显示当前实例的非标准挂载至少包括：`/opt/SothisAI` 对应 `/opt/gridview/scripts/scheduler/slurm/instance`，`/opt/ib_driver` 对应 `/SothisAI/ib_driver`，`/etc/hosts` 对应 `/home/xshu/SothisAI/instance_service/hh1/shared_hosts`，`/etc/motd` 对应 `/home/xshu/SothisAI/instance/ssh/hh1_1_0/motd`，以及整个 `/lenovofs1/home/xshu` 对应 `/home/xshu`；同时存在 NVIDIA 设备和驱动库挂载。
- 从容器内执行 `ssh ... 'ls -la /opt/SothisAI/instance'` 和 `ssh ... 'ls -la /opt/SothisAI/instance_service'` 均返回 `No such file or directory`。
  所以不能通过当前容器内的这两个猜测路径读取 `prepare_container`、参数文件或 `_dockerlist`；`/opt/SothisAI` 在该实例中实际是 GridView 的 `slurm/instance` 挂载，不是宿主 `SothisAI/instance` 树的完整映射。

### 本次结论与剩余限制

- 新证据确认：h1 的脚本部署内容已包含 commit `8f86715...` 的 `start_command()` cluster connect 修复；运行中的 h1 实例具有完整的 master/Web 服务进程和 GridView/NVIDIA/共享 home 挂载。
- 新证据不能确认：GridView 创建 h1 时的原始 `DC_ENTRYPOINT`、`DC_CMD_ARG`、`prepare_container` 参数或 `_dockerlist` 内容。
  原因是这些变量没有留在容器环境中，PID 1 已被覆盖为 sshd，且容器内对应的宿主参数目录不存在；运行进程只能证明服务结果，不能重建原始 `docker run` 命令。
- 因此原“未能确认 live GridView 作业最终参数”的事项被缩小为“需要在有合适测试作业时，从宿主侧只读保存 `prepare_container`、参数文件、`_dockerlist` 和 `scontrol show job`”；本次没有提交新作业，也没有触碰生产作业。

## 2026-09-02 login03 作业 787683 只读记录

本次执行一个有界只读任务：在 login03 查询用户提供的 Slurm 作业 `787683`，并读取其容器启动记录和消息文件。
没有提交、取消或修改作业，没有运行 CryoSPARC `init`/`start`，没有使用 `sudo`，也没有修改生产数据。

### 连接方式与阻塞

- 按仓库约定使用 SSH 配置别名时，`/Users/galaxy/git/szbl-hpc/Qbics/new/ssh/config:37` 的裸 known_hosts 行仍会导致 `Bad configuration option: 10.68.247.43`。
- 本次只读查询改用 `ssh -F /dev/null`，显式指定 `/Users/galaxy/git/szbl-hpc/Qbics/new/ssh/s1_ed25519` 和 `/Users/galaxy/git/szbl-hpc/Qbics/new/ssh/known_hosts`，并设置 `StrictHostKeyChecking=yes`，成功连接 `xshu@10.68.247.43:22`。
- 远端登录环境每次会打印 `error: could not lock config file /lenovofs1/home/xshu/.gitconfig: File exists`；该信息来自登录环境，不属于作业输出，本次没有修改远端 Git 配置。

### Slurm 状态

- 命令：`ssh ... xshu@10.68.247.43 'scontrol show job -dd 787683'`。
- 结果：`JobId=787683`、`JobName=hh1_1_0`、`UserId=xshu(5060)`、`JobState=RUNNING`、最新查询的 `Reason=None`，节点为 `gn02`，分区为 `NV_4090D`。
- 资源：`NumNodes=1`、`NumCPUs=8`、`NumTasks=8`、`TRES=cpu=8,mem=100G,node=1,billing=8,gres/gpu=1`，GPU 为 `NVIDIAGeForceRTX4090D:1`，CPU 为 `0-7`。
- 时间：`SubmitTime=2026-09-02T09:31:02`、`StartTime=2026-09-02T09:31:02`、`EndTime=2026-09-07T09:31:03`。
- 作业命令为 `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/job_xshu_20260902_093102`，工作目录为 `/lenovofs1/home/xshu`，标准输出和错误输出均为 `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683.out`。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/detail.job.787683:1-34` 是启动早期快照，当时为 `JobState=RUNNING Reason=Prolog`、`RunTime=00:00:01`，不能覆盖最新的 `scontrol` 状态。
- `scontrol show step -d 787683` 只读结果显示 `787683.extern` 和 `787683.batch` 均为 `State=RUNNING`，节点为 `gn02`。

### 作业消息

- 命令：`ssh ... xshu@10.68.247.43 'nl -ba /lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683.out'`。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683.out:1-21` 的有效消息为：

```text
1  ======校验作业信息======
2  Wed Sep 2 09:31:03 CST 2026
3  用户身份 : xshu
4  主目录 : /lenovofs1/home/xshu
5  作业类型 : instance
6  作业路径 : /lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0
9  ======开始拉取镜像======
10 Wed Sep 2 09:31:03 CST 2026
11 docker pull image.ac.com:5000/gpu/xshu/base/cryosparc-hybrid:h1
12 ======拉取镜像成功======
14 ======开始启动容器======
15 Wed Sep 2 09:32:28 CST 2026
16 787683_gn02 启动完成
17 ======启动容器成功======
19 ========容器日志========
20 Wed Sep 2 09:32:36 CST 2026
21 sudo: unable to resolve host worker-0: Temporary failure in name resolution
```

- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/prepare_container:1-17` 只记录相同的校验、h1 镜像拉取成功和 `787683_gn02` 启动成功消息，没有额外 CryoSPARC 服务启动消息。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/task.message` 为空，文件大小为 `0` bytes。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/logerr.hh1_1_0` 为空，文件大小为 `0` bytes。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/logout.hh1_1_0:1` 为 `Submitted batch job 787683`。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683_PULL.log` 为 `1216` 行、`215194` bytes；只读检索命中 `Pulling from` 和多条 `Pull complete`，未命中 `Error` 或 `failed`，与 `787683.out:12` 的拉取成功一致。

### 对应容器

- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/_dockerlist_787683:1` 记录容器名 `787683_gn02`、别名 `worker-0`、节点 `gn02`、GPU `0`、状态 `running`、IP `173.0.74.4`、容器 ID `a15ae0679970c4310cf6187fff8b5e68de3a982a7ca518f1b176efe03f3f577f`。
- 同一行记录 CPU `8`、内存 `102400`、GPU `1`、容器端口 `8888`，`HOSTPORT` 为空；没有发现 `-p` 端口发布参数。
- 同一行的关键挂载为 `/lenovofs1/home/xshu/SothisAI/instance_service/hh1/shared_hosts:/etc/hosts`、`/opt/gridview/scripts/scheduler/slurm/instance/:/opt/SothisAI/`、`/lenovofs1/home/xshu:/lenovofs1/home/xshu:rw`、`.ai_user_info/ai_sudoer:/etc/sudoers.d/ai_sudoer:ro`、作业 `motd:/etc/motd` 和 `/lenovofs1/SothisAI/ib_driver/:/opt/ib_driver/:ro`。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/hh1_1_0_1788312662471.json:1` 的非敏感字段确认 `taskType=ssh`、`taskName=hh1_1_0`、`instanceId=2094961263481708547`、镜像为 `image.ac.com:5000/gpu/xshu/base/cryosparc-hybrid:h1`、CPU `8`、GPU `1`、内存 `102400`、`containerPort=8888`、`useStartScript=false`、共享路径 `/lenovofs1/SothisAI`。

### 实际 runtime 参数

- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683_gn02:1-29` 保存生成参数：`:1-12` 为 worker、节点 `gn02`、GPU `0`、别名 `worker-0`；`:16-18` 为 `DC_HOST_PORT=""`、`DC_CONTAINER_PORT="8888"`、`SHARING_PATH="/lenovofs1/SothisAI"`；`:21` 为 `--cpuset-cpus=0,1,2,3,4,5,6,7`、`--memory=102400M`、`--shm-size=102400M`；`:27` 为 `DC_ENTRYPOINT=" --entrypoint /bin/sh "`；`:28` 为 h1 镜像；`:29` 的 `DC_CMD_ARG` 以 `-c` 开始，运行用户/组/影子密码、sudoers、profile 和 sshd 配置后以 `/usr/sbin/sshd` 结束。
- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/prolog.env.787683.gn02:137-146` 的最终 GPU 命令以 `NV_GPU=0 timeout 90m nvidia-docker run` 开始，包含 `--name 787683_gn02`、`-d`、`--hostname=worker-0`、CPU/内存/shm 限制、shared hosts 和上述 GridView 挂载、`--env JUPYTERLAB_WORKSPACES_DIR=...`、`--cap-add=SYS_PTRACE`、`--security-opt seccomp=unconfined`、`--entrypoint /bin/sh` 和 h1 镜像。
- 同一最终命令的容器 command 是运行时配置脚本加 `/usr/sbin/sshd`，没有调用 `/usr/local/bin/cryosparc-container`、`/usr/local/bin/cryosparc-workstation` 或 `/usr/local/bin/cryosparc`。
- 因此已完成此前“需要从 live 作业宿主侧只读保存 `prepare_container`、参数文件、`_dockerlist` 和 `scontrol show job`”的未完成事项，以及“确认 GridView runtime command 是否显式启动 CryoSPARC wrapper”的下一次会话建议。该作业的 GridView 创建命令只保证 sshd 容器启动，不能证明 CryoSPARC master/worker 由该命令启动。

### Hostname 警告核对

- 命令：`ssh ... xshu@10.68.247.43 'wc -l -c /lenovofs1/home/xshu/SothisAI/instance_service/hh1/shared_hosts; grep -nE "worker-0|173\\.0\\.74\\.4" /lenovofs1/home/xshu/SothisAI/instance_service/hh1/shared_hosts'`。
- `/lenovofs1/home/xshu/SothisAI/instance_service/hh1/shared_hosts:3` 为 `173.0.74.4 worker-0`，文件共 `3` 行、`168` bytes。
- 结论：已排除 shared hosts 文件中完全缺少 `worker-0` 这一原因；没有继续修改 hosts、容器或作业，也没有据此断言具体的解析时机/namespace 原因。

### 凭据处理与剩余限制

- `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/hh1_1_0_1788312662471.json:1` 含 `sshPassword` 字段；`/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/787683_gn02:29` 和 `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/prolog.env.787683.gn02:29,146` 的生成参数/命令中也包含对应临时凭据。
- 本文档不记录该凭据的值；查询时仅将其脱敏后用于确认命令结构，没有执行包含该值的命令。若该凭据仍有效，应由 GridView 平台按既有机制失效或轮换。
- 当前作业已提供实际 h1 runtime 参数，但没有证明运行中的 CryoSPARC 服务是由该次 `nvidia-docker run` 启动；服务进程来源仍需另有可审计的启动记录，不能通过重复检查本作业的已确认参数解决。
