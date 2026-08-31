# CryoSPARC 集群适配记录

本文记录 workstation 容器接入 Slurm 集群、注册 worker、生成作业脚本、容器网络、服务生命周期和已修复问题。

记录日期：2026-08-27。

## 1. 网络拓扑与地址职责

当前测试环境中的关键地址如下：

| 地址或端口 | 用途 |
| --- | --- |
| `10.68.247.45` | workstation 容器对外的 NAT 服务器地址 |
| `40008` | 通过 NAT 访问容器 SSH 的外部端口 |
| `173.0.75.3` | workstation 容器的可达 IPv4，计算节点可以直接访问 |
| `10.10.5.1` | 临时用于网络和 mDNS 验证的计算节点 |
| `127.0.0.1` | 仅用于容器内部的本地健康检查 |

外部 SSH 端口可能随测试容器实例变化。
2026-08-28 对运行中容器的实际入口是 `ssh -p 40001 xshu@10.68.247.45`；此前的 `40008` 仍是另一实例/测试入口，不能将端口号写死为容器内部地址。

容器内的 CryoSPARC 服务端口如下：

| 端口 | 服务 |
| --- | --- |
| `61000` | Web 应用 |
| `61001` | MongoDB |
| `61002` | API |
| `61003` | command_vis |
| `61004` | Redis |
| `61005` | supervisord 控制端口 |
| `61006` | app_api |

`containers/cryosparc5/cryosparc:277-292` 和 `:302-315` 使用 `127.0.0.1` 检查 API 与 Web，是容器内的正确行为。

Slurm 作业运行在计算节点上，作业中的 `--master` 必须使用计算节点可以访问的地址，即当前环境中的 `173.0.75.3`，不能使用只在容器内部可解析的 `worker-0`。

## 2. 集群提交配置

固定集群配置文件为：

```text
/opt/cryosparc/cryosparc_master/bin/cluster_info.json
/opt/cryosparc/cryosparc_master/bin/cluster_script.sh
```

`containers/cryosparc5/cryosparc:528-545` 在初始化时分别调用 `connect_worker()` 和 `connect_cluster()`，因此容器内本地 worker 与 Slurm cluster lane 是两个独立的调度目标。

`containers/cryosparc5/cryosparc:343-348` 允许通过 `CRYOSPARC_CLUSTER_ENABLED=false` 禁用自动 cluster 注册，但不会禁用本地 worker 注册。

仓库中的 `containers/cryosparc5/cluster_info.json:2-12` 当前关键配置为：

```json
{
    "send_cmd_tpl": "ssh 12.12.4.3 {{ command }}",
    "qsub_cmd_tpl": "sbatch {{ script_path_abs }}",
    "qstat_cmd_tpl": "squeue -j {{ cluster_job_id }}",
    "qdel_cmd_tpl": "scancel {{ cluster_job_id }}",
    "qinfo_cmd_tpl": "sinfo",
    "worker_bin_path": "/lenovofs1/software/apps/cryosparc/5.0.7/cryosparc_worker/bin/cryosparcw"
}
```

`send_cmd_tpl` 中的 `12.12.4.3` 只表示 master 通过 SSH 向集群提交 `sbatch`、查询或取消作业时使用的登录地址。

它不决定作业运行时连接哪个 CryoSPARC master，也不会修改作业脚本中的 `--master` 参数。

集群配置和运行时 master 地址是两个独立的概念：

| 配置 | 作用 |
| --- | --- |
| `cluster_info.json:2` 的 `send_cmd_tpl` | master 到集群登录节点的 SSH 路径 |
| `cluster_info.json:3-6` | `sbatch`、`squeue`、`scancel` 和 `sinfo` 命令 |
| `CRYOSPARC_MASTER_HOSTNAME` | worker 和 Slurm 作业访问 master 的地址 |
| `cluster_script.sh:20` 的 `{{ run_cmd }}` | CryoSPARC 渲染出的实际 worker/job 命令 |

## 3. Master 地址问题与修复

### 3.1 原因

旧版 `containers/cryosparc5/cryosparc:52-60` 的 `detect_hostname()` 只调用 `hostname -f`，容器 hostname 为 `worker-0` 时，就会把以下值写入 runtime config：

```bash
CRYOSPARC_MASTER_HOSTNAME=worker-0
```

容器内部 `/etc/hosts` 可以解析 `worker-0`，但计算节点没有这个解析记录，因此 Slurm 作业会出现：

```text
worker-0:61001: [Errno -2] Name or service not known
```

`ex/cryosparc_master/core/database_management.py:204-213` 会直接使用 `master_hostname` 生成 MongoDB URI，因此 hostname 不可解析时，作业不仅无法访问 API，也无法访问 `61001` 的 MongoDB。

`CRYOSPARC_FORCE_HOSTNAME=true` 只绕过 CryoSPARC 的本机 hostname 安全检查，不会把 hostname 转换成 IP。

另外，已有作业的 `queue_sub_script.sh` 是生成时固化的文件。

修改 runtime config 不会自动改写已经生成的作业脚本。

### 3.2 启动时刷新 IPv4

`CRYOSPARC_MASTER_HOSTNAME` 是当前容器运行状态，不是容器网络配置。容器每次重新创建后，Docker 可能从允许的地址范围分配不同的 IP，因此不能把上一次启动探测到的 IP 当作下一次启动的输入。

当前 `containers/cryosparc5/cryosparc` 的行为由
`/opt/cryosparc/cryosparc_master/bin/cluster_info.json` 是否存在决定：

1. 文件存在时，`start`、`restart` 或初始化真正启动核心服务前，`start_core_services()` 重新从默认路由的 source IPv4 获取当前地址。
2. 文件存在且显式设置 `CRYOSPARC_MASTER_HOSTNAME` 为纯 IPv4 时，保留该值，便于多网卡环境选择计算节点可达的网卡；显式 hostname 不覆盖集群模式的 IPv4 逻辑。
3. 文件不存在时，启动使用容器 hostname，并跳过自动 `cluster connect`，适用于不带集群配置的纯 workstation 变体。
4. 地址结果先写入 `${HOME}/.cryosparc/master/config.sh`，再启动 MongoDB、API 和其他服务，确保它们使用同一个当前地址。
5. `status`、`env`、`stop` 等非启动命令只读取 runtime config 中最近一次成功写入的地址，不会在服务运行期间自行覆盖配置。

单节点 MongoDB 不需要随容器 IP 变化而导出/导入数据或重建 replica set：`ex/cryosparc_master/core/database_management.py:85-107` 初始化的成员地址是 `localhost:61001`，`ex/cryosparc_master/core/database_management.py:216-224` 也使用 `directConnection=True`。启动时需要更新的是 CryoSPARC 访问 MongoDB 所用的 master 地址，而不是 MongoDB 数据目录中的成员地址。

集群配置存在时，`detect_master_address()` 的探测顺序为：

1. 使用 `ip -4 route get 1.1.1.1` 提取默认路由的 source IPv4。
2. 如果没有默认路由，回退到第一个 `scope global` IPv4。
3. 如果系统没有 `ip`，回退到 `hostname -I`。
4. 没有 IPv4 时才回退到 hostname。

Dockerfile 已在 `containers/cryosparc5/Dockerfile:31-49` 安装 `iproute2`，因此正式镜像具备该检测能力。

`CRYOSPARC_MASTER_HOSTNAME_AUTO` 只记录这次地址是否由自动探测得到，不再作为下一次启动保留旧 IP 的依据。

多网卡环境如果默认路由不是计算节点可达的网络，应显式设置纯 IPv4 的
`CRYOSPARC_MASTER_HOSTNAME`，并在每次启动时继续提供该环境变量，或者将其配置在容器的固定环境中。

### 3.3 Worker 注册

`containers/cryosparc5/cryosparc` 的 `connect_worker()` 使用以下参数注册 worker：

```text
--master ${MASTER_HOSTNAME}
--port ${BASE_PORT}
--worker ${WORKER_NAME}
--sshstr ${SSH_STRING}
--ssdpath ${SCRATCH_PATH}
--ssdreserve ${SSD_RESERVE}
```

其中：

- `--master` 必须是计算节点和容器内都能访问的 master 地址，当前应使用可达 IPv4，而不是仅容器内部可解析的 `worker-0`。
- `CRYOSPARC_WORKER_NAME` 可以显式覆盖本地 worker 的注册名；未显式指定时，当前脚本将同容器 worker 注册为 `localhost`，不使用平台提供的 `worker-0`、`worker-1` 等容器 hostname。
- `CRYOSPARC_SSH_USER` 和 `CRYOSPARC_SSHSTR` 可以显式指定 worker SSH 用户和连接字符串。
- 未显式指定 `CRYOSPARC_SSHSTR` 时，当前脚本默认使用 `${SSH_USER}@localhost`，因为受管理的本地 worker 与 master 位于同一个容器。
- 对本地 worker，`--worker` 和 `--sshstr` 默认都使用 localhost 语义；`localhost` 不能替代 Slurm 作业中的 `--master`，计算节点仍必须使用可达的 master IP 或稳定 DNS 名称。

修改 master 地址后，应重新执行 worker 注册。

如果已有本地 worker 是按旧 IP、`worker-0` 或 `worker-1` 注册的，切换为 `localhost` 后会产生一次新的 worker target；确认新 target 正常后，应在 CryoSPARC 中移除旧 target。

新提交的作业会使用新的 master 地址；已有作业需要重新生成或重新提交其 `queue_sub_script.sh`。

## 4. Slurm 作业脚本与资源绑定

### 4.1 运行中作业的检查路径

作业文件位于登录节点可访问的共享文件系统上，不需要登录实际计算节点读取。
当前验证过的路径是：从 `ln03` 查询 Slurm 作业，再将小文件 `scp` 到本地用 `Read` 或 `sed` 分析。

运行中作业的 `NodeList` 可以通过 `scontrol show job -dd <job_id>` 获取；例如作业 `785203` 的实际节点是 `gn03`，因此需要检查计算节点运行态时，可以从 `ln03` 执行 SSH 到 `gn03`，但不能假设真实节点上的普通用户拥有 `sudo` 或 Docker socket 权限。

作业 `785203` 的脚本为：

```text
/lenovofs1/home/xshu/SothisAI/instance/ssh/v12_1_0/job_xshu_20260828_111215
```

该脚本的关键行为如下：

- 第 12-23 行设置作业目录、加载 `/opt/gridview/slurm/etc/sothisai/function.sh`、计算 `dockername` 并启动容器监控。
- 第 13-15 行对 `prepare_container` 执行 `cat`，所以该文件是启动日志，不是由 batch script 执行的容器启动命令。
- 第 29 行调用平台预先生成的 `/usr/bin/sudo /usr/bin/ai_docker logs -f ${dockername}`；这是作业模板中的平台命令，不能作为交互用户在 `gn03` 上可以使用 `sudo` 的依据。
- 第 35-56 行只轮询 `getDockerStatus` 并在容器退出时写入 `task.message`。

实际容器运行信息记录在：

```text
/lenovofs1/home/xshu/SothisAI/instance/ssh/v12_1_0/_dockerlist_785203
```

该文件记录 `ALIAS=worker-0`、`NAME=785203_gn03`、`NODE=gn03`、`IPADDR=173.0.71.3`，并记录了以下关键挂载：

```text
/lenovofs1/home/xshu/SothisAI/instance_service/v12/shared_hosts:/etc/hosts
```

其 MOUNT 列表没有显式的 `/etc/hostname` 挂载。
Docker 为容器提供的 `/etc/hostname` 仍应以容器自己的 hostname 配置为准；2026-08-28 从 `ssh -p 40001 xshu@10.68.247.45` 观察到 `/etc/hostname` 内容为 `worker-0`。

当前 `shared_hosts` 内容为：

```text
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
173.0.74.4 worker-0
173.0.71.3 worker-0
```

因此平台当前同时把两个容器 IP 映射为同一个 `worker-0`，解析顺序具有歧义。
worker 数据库名称可以稳定使用 `worker-0`，但 master 连接地址仍应使用实际可达 IP，并应避免依赖这个包含重复 IP 的 `/etc/hosts` 条目作为唯一网络发现机制。

`containers/cryosparc5/cluster_script.sh:2-20` 负责渲染 Slurm 作业脚本：

- 作业目录使用 `#SBATCH --chdir={{ job_dir_abs }}`。
- 作业名包含 project UID 和 job UID。
- GPU 请求为 `#SBATCH --gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}`，至少申请一张 GPU，多 GPU 作业按 `num_gpu` 动态申请。
- 分区固定为 `NV_4090D`。
- 作业启动前从 `${HOME}/.cryosparc/license_id` 读取 license，并通过 `CRYOSPARC_LICENSE_ID` 导出。
- 镜像和 cluster template 不保存真实 license 值。
- `{{ run_cmd }}` 由 CryoSPARC 渲染，实际包含 `cryosparcw --master ... --port 61000` 等运行参数。

当前集群使用 `select/cons_tres`、GRES、`task/affinity` 和 `task/cgroup` 管理资源。

`NV_4090D` 分区的默认资源按 GPU 提供 CPU 和内存，因此模板没有额外固定 `--cpus-per-task` 或 `--mem`。

GPU 绑定验证结果：

- 单 GPU 作业只看到一张 RTX 4090 D，`CUDA_VISIBLE_DEVICES=0`。
- 双 GPU 作业看到 `CUDA_VISIBLE_DEVICES=0,1`。
- `SLURM_JOB_GPUS` 是节点物理 GRES 编号，和作业内重映射后的 `CUDA_VISIBLE_DEVICES` 不一定相同。

修改 `cluster_info.json` 或 `cluster_script.sh` 后，必须重新执行：

```bash
cryosparcm cluster connect
```

因为首次初始化会注册 cluster lane，之后普通 `start` 或 `restart` 不会自动重新读取模板并更新数据库配置。

## 5. mDNS 验证结论

测试容器中曾临时安装：

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    avahi-daemon avahi-utils libnss-mdns dbus
```

手动启动 D-Bus 和 Avahi 后，容器可以广播并解析：

```text
worker-0.local -> 173.0.75.3
```

从 `10.10.5.1` 通过 Docker bridge 地址发送 mDNS 查询时，也能得到 `173.0.75.3`。

但从计算节点的 IB 地址 `10.10.5.1` 通过 `ib0` 查询 `224.0.0.251:5353` 会超时。

结论是：

- Avahi 在容器网络命名空间内工作正常。
- Docker bridge/veth 到 IB 网络之间没有转发 mDNS 组播。
- `worker-0.local` 不能作为跨该网络的可靠 master 地址。
- 当前应直接使用计算节点可达的 `173.0.75.3`。
- 如果以后必须使用 `.local` 名称，需要在宿主机配置 Docker bridge 到 IB 的 mDNS reflector，或者使用 host network/DNS；仅在容器内安装 Avahi 不够。

Avahi 当前只是测试依赖，没有集成到 `containers/cryosparc5/entrypoint:5-35`，容器重启后不会自动启动。

## 6. 服务启动、PID 和端口问题

### 6.1 61002 等待问题

旧版 `supervisor_running()` 只检查 PID 文件中的进程是否存活。

当 supervisor 还活着但 database、Redis 和 API 都没有启动时，workstation 脚本会错误地跳过 `cryosparcm start`，然后直接等待 `127.0.0.1:61002`。

当前 `containers/cryosparc5/cryosparc:202-214` 除了检查 PID，还验证进程命令行中包含 `supervisord` 和 `${MASTER_ROOT}`。

`containers/cryosparc5/cryosparc:216-220` 的 `api_listening()` 检查 API 监听状态。

如果 supervisor 存活但 API 没有监听，`containers/cryosparc5/cryosparc:234-275` 会执行 `cryosparcm restart`，而不是把残留 supervisor 当作完整启动状态。

### 6.2 PID 文件位置

PID 文件已从 home 下的 runtime 目录移动到：

```text
/var/run/cryosparc-supervisord.pid
```

Dockerfile 的相关逻辑位于：

- `containers/cryosparc5/Dockerfile:123`：先复制 installer 阶段的 `/opt/cryosparc`。
- `containers/cryosparc5/Dockerfile:130`：设置 `CRYOSPARC_SUPERVISOR_PID_FILE`。
- `containers/cryosparc5/Dockerfile:145-148`：修改 supervisord 配置并执行 `mkdir -p /var/run && chmod 777 /var/run`。

这样 supervisor PID 跟随容器运行时文件系统，不会继续遗留在 home volume 中。

旧镜像升级后，如果仍看到 `$HOME/.cryosparc/master/run/supervisord.pid`，说明容器还没有使用包含该改动的新镜像。

### 6.3 61001 冲突误报

`TIME-WAIT` 不等于有软件监听端口。

判断监听进程应使用：

```bash
sudo ss -ltnp 'sport = :61001'
```

`ex/cryosparc_master/cli/env.py:123-168` 和 `ex/cryosparc_master/core/services.py:79-87` 都通过 socket bind 检查端口。

当 `CRYOSPARC_MASTER_HOSTNAME` 被错误写成 `173.0.75.3/24` 时，`socket.bind()` 会失败，上层将普通 bind 错误误报为 61001 被占用。

当时 `ss` 只有 61001 相关的 `TIME-WAIT`，没有 `LISTEN`；将配置修正为纯 IPv4 后，database、API 和其他服务均恢复正常。

`cryosparcm restart` 不会强制杀掉未知程序的监听进程。

如果确实存在其他程序的 `LISTEN`，应先确认 PID 和进程归属，再停止冲突程序；不能根据 `TIME-WAIT` 记录直接执行 `kill -9`。

## 7. 镜像构建缓存

`containers/cryosparc5/Dockerfile` 当前使用三个最终 target：

```dockerfile
FROM master0 AS master

COPY --chmod=644 containers/cryosparc5/cluster_info.json /opt/cryosparc/cryosparc_master/bin/cluster_info.json
COPY --chmod=644 containers/cryosparc5/cluster_script.sh /opt/cryosparc/cryosparc_master/bin/cluster_script.sh

FROM master0 AS workstation

COPY --from=installer /opt/cryosparc/cryosparc_worker /opt/cryosparc/cryosparc_worker

FROM workstation AS hybrid

COPY --chmod=644 containers/cryosparc5/cluster_info.json /opt/cryosparc/cryosparc_master/bin/cluster_info.json
COPY --chmod=644 containers/cryosparc5/cluster_script.sh /opt/cryosparc/cryosparc_master/bin/cluster_script.sh
```

installer 阶段会统一执行 `chmod -R a+rwX /opt/cryosparc`，因此三个 target
从 installer 复制时都会保留运行用户可写权限。

master target 包含 cluster 配置但不包含 worker 文件；workstation target 只追加 worker，
不包含 cluster 配置；hybrid target 在 workstation 基础上追加 cluster 配置。
修改运行时环境变量不会使安装阶段的大复制层失效。

构建日志中如果 installer 阶段显示 `Using cache`，但某个最终 target 重新执行，首先检查
该 target 的上下文脚本、cluster 配置和 target 选择是否发生变化。

## 8. 推荐操作流程

新容器或清理过 runtime config 的容器：

```bash
cryosparc init
cryosparc status
```

需要显式固定计算节点可达地址时：

```bash
export CRYOSPARC_MASTER_HOSTNAME=173.0.75.3
cryosparc restart
cryosparc status
```

验证容器内服务：

```bash
ss -ltnp
curl --noproxy '*' -H "License-ID: ${CRYOSPARC_LICENSE_ID}" \
    http://127.0.0.1:61002/
```

验证计算节点到容器的直接连接时，应测试 `173.0.75.3`，不要只测试 mDNS：

```bash
curl --noproxy '*' http://173.0.75.3:61000/
```

修改 worker 或 cluster 配置后，应依次确认 runtime config、worker 注册结果和新生成的作业脚本中的 `--master` 值。

已有作业不会自动更新，必须重新生成 queue script 或重新提交作业。

生产容器禁止未经确认执行 `reset data` 或 `reset all`。

## 9. 相关提交

| Commit | 内容 |
| --- | --- |
| `16ddfde` | 将 cluster 提交命令中的登录节点从 `login03` 改为 `12.12.4.3` |
| `b3c37be` | 调整 workstation cluster runtime settings |
| `b399111` | 改进 supervisor 状态识别和 master/API 启动流程 |
| `907671e` | 默认使用容器可达 IPv4，并迁移旧 hostname/CIDR runtime 值 |

后续修改 cluster 模板、master 地址选择、worker 注册或服务生命周期时，应同步更新本文档和 live test 结果。
