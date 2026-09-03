# CryoSPARC 生命周期研究进度

## 当前状态

本轮补充工作已完成：官方资料、当前安装包、master/worker 源码、容器包装层和生命周期相关提交均已核验，本文现为最终研究报告。

已在 gpu14 的 `~/git/Container-CryoSPARC` 中完成隔离的 Podman 镜像构建、CryoSPARC `init`/`start`、本地 GPU worker 注册和容器 `stop`/`start` 回归。

仍未使用真实 license 提交作业、验证跨主机 SSH/shared filesystem 或提交真实 Slurm 作业，也没有执行破坏性 reset；这些边界仍属于后续运行态验证。

工作区：`/Volumes/Develop/git/szbl-hpc/CryoSPARC`

图谱项目：`CryoSPARC`

图谱 generation/index time：`2026-08-17T02:25:43Z`；本轮对 metadata changed、not tracked 和归档路径全部使用直接源码复核。

当前安装包版本：master/worker 均为 `v5.0.7`，revision 均为 `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`。

本次只更新本文件；工作区原有的 `ex/`、`pkg/` 等未跟踪安装包材料和其他用户变更未被回滚或改写，未提交。

## 已完成结果

### 1. 仓库与图谱状态

- `codebase-memory-mcp_list_projects` 确认项目 `CryoSPARC`，分支 `main`，节点 15664、边 83754。
- `codebase-memory-mcp_index_status` 返回 `ready`。
- 图谱命中：
  - `CryoSPARC.ex.cryosparc_master.core.instance.startup`，`ex/cryosparc_master/core/instance.py:142-192`。
  - 图谱曾命中 `CryoSPARC.ex.cryosparc_worker.core.instance.startup`，但当前工作区没有对应展开路径；worker 结论改用归档直接读取结果。
  - 直接源码核验使用 `ex/cryosparc_master/core/core.py:50-85`；worker 对应文件通过归档核对。
- `trace_path` 对 master/worker `startup` 做了双向调用追踪；master 出站可达 226 个节点，worker 出站可达 223 个节点，worker 的调用者包含 `start`。
- `check_index_coverage` 结果：`containers/cryosparc5` 不在图谱跟踪；worker 展开路径在当前工作区不存在；master lifecycle 文件没有记录的 parse gap，但部分文件 metadata 已变化，因此最终结论仍应以直接源码为准。
- 当前工作区 `/ex` 目录只有 `ex/cryosparc_master/`，没有展开的 `ex/cryosparc_worker/`。
- `pkg/cryosparc_worker.tar.gz` 存在，归档内确认包含 worker 安装器、`bin/cryosparcw`、`core/` 和 `config/`；归档版本和 revision 已与 master 包交叉核对。

### 2. 安装过程

master 入口：

`ex/cryosparc_master/install.sh:2-5`

该 wrapper 计算 `ROOT_DIR`，然后 source `install/install_master.sh`。

master 安装器：

`ex/cryosparc_master/install/install_master.sh`

- `:67-88` 设置默认值：hostname 来自 `hostname -f`，`BASE_PORT=61000`，默认 DB 为 master 目录上级的 `cryosparc_database`，默认启用 DB auth，默认非 standalone。
- `:90-189` 解析 `--license`、`--hostname`、`--port`、`--dbpath`、`--standalone`、`--worker_path`、初始用户参数、`--ssdpath`、`--allowroot`、`--yes`、`--disable_db_auth` 和 `--ignore-port-conflicts` 等选项。
- `:191-231` 检查 license、`curl`、Linux/Darwin、x86_64 和 master hostname 解析。
- `:241-282` 默认检查 `BASE_PORT` 到 `BASE_PORT+10` 的端口范围、非特权端口、ephemeral 端口冲突和端口占用。
- `:284-318` standalone 强制要求 `WORKER_PATH`、初始用户 email/username/firstname/lastname；未提供 password 时交互读取；root 安装需要 `--allowroot` 或交互确认。
- `:371-420` 创建 DB 目录并重写 master `config.sh`，写入 license、master hostname、DB path、base port、`CRYOSPARC_INSECURE`、`CRYOSPARC_DB_ENABLE_AUTH`，以及可选 development/click-wrap 配置。
- `:422-442` 非 development 模式执行 `./bin/cryosparcm deps`，之后执行 `eval "$(./bin/cryosparcm env)"`。
- `:454` 调用 `check_and_offer_patch_install`；该函数在 `:48-65` 中执行 `cryosparcm patch`，失败时输出“No patches installed”但继续安装流程。
- `:474-481` 可将 master `bin` 目录追加到 Linux `~/.bashrc` 或 Darwin `~/.bash_profile`。
- standalone 分支 `:483-524` 依次执行 `cryosparcm start`、检查/创建首用户、进入 `WORKER_PATH` 执行 worker `install.sh --license ... --standalone`，再运行 `bin/cryosparcw connect --worker ... --master ... --port ...`。
- 非 standalone 分支 `:525-540` 不启动 master、不创建初始用户、不安装 worker，只提示之后执行 `cryosparcm start` 并另行连接 worker。

worker 安装器没有在当前工作区展开；已将归档只读展开到 `/tmp/cryosparc-worker-read`，并从 `pkg/cryosparc_worker.tar.gz` 读取以下归档成员：

- `cryosparc_worker/install.sh:1-5`：source `install/install_worker.sh`；归档内 `version` 为 `v5.0.7`，`revision` 为 `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`。
- `cryosparc_worker/install/install_worker.sh:30-70,72-83,98-106,120-182`：默认 `GPU=true`、`STANDALONE=false`，解析 `--license`、`--yes`、`--nogpu`、`--standalone`；检查 OS/x86_64；默认检查 `nvidia-smi` 但缺失时 warning；写入 worker `config.sh` 的 license；非 development 模式执行 `./bin/cryosparcw deps`；安装结束只提示连接 master。`--nogpu` 是安装阶段的 GPU 检查开关，不等同于 connect 阶段的 `--no-gpu`；其中 `:77-83` 仍有未初始化的 `SSD`/`SSD_PATH` 分支，SSD 路径、quota 和 reserve 实际应在 connect 阶段配置。
- `cryosparc_worker/install/install_deps.sh`：按 `deps_hashes` 与 `deps_bundle_hashes` 的 hash 决定是否安装 Python 和 external dependencies。
- `cryosparc_worker/bin/cryosparcw:39-45,47-124,132-195`：读取 worker `config.sh`，处理 update/deps，激活 bundled `.pixi/envs/worker`，设置 `PYTHONPATH`、Numba、线程和 Python 3.12 `LD_PRELOAD`，最后 exec `cli/cryosparcw.py`；没有启动 worker 常驻 daemon 的路径。
- 归档内 `cli/cryosparcw.py`、`cli/connect.py`、`cli/worker.py` 与 master 对应源码相同；因此 worker 连接逻辑以 `ex/cryosparc_master/cli/connect.py:81-200` 等直接源码行号核对。

依赖安装：

`ex/cryosparc_master/install/install_deps.sh:21-69,75-98`

接受 `--master|--worker` 和 `--force`，hash 未变化时跳过安装；master/worker 的 Python 环境和 external dependencies 均来自安装包内 bundle，而不是此处现场从 PyPI 下载。

### 3. master start 调用链

master shell CLI：

`ex/cryosparc_master/bin/cryosparcm:115-136,460-516`

- 从 `${CRYOSPARC_CONFIG_DIR:-root_dir}/config.sh` source 配置。
- 要求 `CRYOSPARC_LICENSE_ID`、`CRYOSPARC_BASE_PORT`、`CRYOSPARC_DB_PATH` 已设置。
- 默认设置 `CRYOSPARC_ROOT_DIR`、`CRYOSPARC_MASTER_HOSTNAME`、`CRYOSPARC_FORCE_USER=false`、`CRYOSPARC_FORCE_HOSTNAME=false`、`CRYOSPARC_LICENSE_SERVER_ADDR=https://get.cryosparc.com`。
- 普通 CLI 调用设置 Python env、`PATH`、`PYTHONPATH`、`NUMPY_MADVISE_HUGEPAGE=0`、`MKL_NUM_THREADS=1`、`NUMEXPR_NUM_THREADS=1`、`OMP_NUM_THREADS=1`、Python 3.12 的 `LD_PRELOAD`，然后 exec `cli/cryosparcm.py`。

Python start：

`ex/cryosparc_master/cli/cryosparcm.py:135-238`

1. 读取 DB 空间并检查 base-port 冲突。
2. `start_supervisor()` 启动 supervisord，或发现已运行时返回。
3. `database.configure()`，随后启动 supervisor service `database` 并 `database.check()`。
4. 启动 `cache`，通过 `try_service_connection(5, core.startup)` 验证 Redis/Core 连接。
5. 若 `startup=true`，调用 `instance.startup()` 做实例初始化、配置写入、license/migration/index/job-register 等启动工作。
6. 启动 `api`，等待 HTTP API；若 `startup=true`，调用 `PUT /start`。
7. `PUT /start` 对应 `ex/cryosparc_master/api/main.py:178-188`，会记录实例信息、后台刷新 worker nodes、清理 deleted projects。
8. 若 `startup=true`，启动 `scheduler`。
9. 启动 `command_vis`。
10. 默认启动 `app` 和 `app_api`。

supervisor 环境与服务：

`ex/cryosparc_master/cli/supervisor.py:27-64,67-177`

- `get_supervisor_env()` 将 Python 当前环境与运行时配置合并。
- 传入 supervisord 的关键值包括 master hostname、root/config/log/DB 目录、Mongo/Redis/API/command/Web/legacy/supervisor 端口、Mongo URI、DB auth flag、Mongo tuning 和 API process 数量。
- `ex/cryosparc_master/config/supervisord.conf:4-94` 的服务均为 `autostart=false`，实际顺序由 `cryosparcm start` 控制；database 使用 `mongod`，cache 使用 `redis-server`，api 使用 `uvicorn`，scheduler 使用 `python -m scheduler`，Web/Live 使用 Node。

实例 startup：

`ex/cryosparc_master/core/instance.py:142-192`

依次自动写入版本/patch、采集实例信息、审计启动、初始化 lanes/targets/默认配置、检查/加载 license、清理并建立 DB indexes、生成 instance UID、写入 settings/job types、执行 migrations、保存 job registers/benchmark/blueprint/workflow references、暂停运行中 sessions、清理 notifications，最后写入 run version file。

底层 Core startup：

`ex/cryosparc_master/core/core.py:50-85`

默认从环境构造 `CoreSettings`，连接 MongoDB、创建 GridFS、连接 Redis Livestore；master 模式还创建 Athena/webhook client。

### 4. 容器 init/start 链

`containers/cryosparc5/entrypoint:5-35`

- `CRYOSPARC_START_SSHD` 默认 `true`。
- root 下生成 SSH host keys，若 22 未监听则启动 `/usr/sbin/sshd`。
- 执行 `/usr/local/bin/cryosparc "$@"`。
- `INT/TERM` trap 调 `cryosparc stop`。
- 最后以 `sleep` 循环保持容器存活，因为 supervisor 服务是 daemonized。

`containers/cryosparc5/cryosparc:1019-1024,1026-1094`

- 无参数严格执行 `init_command`、`start_command`、`status_command`、异步 master 文件预热。
- `init_command:734-751`：已有 DB 时跳过；否则收集首用户、读取/保存 license、启动 master core services、创建 admin user、写 `.initialized` marker、连接本地 worker、连接 cluster。
- `start_command:753-774`：未 initialized 时失败；若 supervisor+Web 已运行则跳过或刷新 local worker resources；否则启动 core services、清理非 cluster resources、连接 local worker 并连接 cluster。已运行 fast path 不会重复执行 `connect_cluster`，cluster 文件新增或变更后应显式执行 `cryosparcm cluster connect`，或先 restart。
- `start_core_services:554-564`：刷新 hostname/no_proxy/SSH、写 runtime config、创建 DB/scratch/projects、调用 master CLI start、等待 API、启动 `scheduler command_vis app app_api`、等待 Web。
- `connect_worker:511-543`：切换到 worker runtime config/log；若 `CRYOSPARC_NOGPU=true`、无 `nvidia-smi` 或 `nvidia-smi -L` 失败则追加 `--no-gpu`；执行 worker `connect`；最后切回 master config/log。
- `connect_cluster:545-552`：`CRYOSPARC_CLUSTER_ENABLED` 默认 true；只有两个 cluster 文件都存在时执行 `cryosparcm cluster connect`。

### 5. standalone 与分离式安装的已知差异

| 项目 | standalone workstation | master/worker 分离 | cluster/Slurm |
|---|---|---|---|
| master 安装 | `--standalone`，需要 `--worker_path` 和初始用户参数 | 非 standalone master 安装 | 仍是非 standalone master 安装 |
| master start | 安装器内自动执行 | 安装完成后手工 `cryosparcm start` | 同左 |
| worker | 同机安装并通过 `cryosparcw connect` 注册 | GPU 节点单独安装，再 connect | 计算节点由调度器按提交脚本启动，不是普通常驻 worker daemon |
| DB/Web/API | master 侧统一运行 | master 侧运行 | master 侧运行 |
| GPU 检查 | worker install/connect 阶段；容器 wrapper 可自动追加 `--no-gpu` | worker install/connect 阶段 | 由 cluster job 分配 GPU，脚本负责运行 worker command |
| scheduler target | local node target | node target，保存 SSH、资源和 worker bin path | cluster target，保存 qsub/qstat/qdel/qinfo/send/script 模板 |
| 文件系统/网络 | 同一容器/主机本地路径 | 官方要求所有节点按相同绝对路径访问 shared filesystem，master 到普通 worker passwordless SSH，worker 可访问 master 的连续端口 | 由 scheduler 和 cluster 模板负责远程提交/监控；cluster master/login 节点必须持续运行 |

## 官方资料核验

以下链接均为 CryoSPARC 官方 Guide 页面；它们用于区分产品要求与本仓库容器实现。

| 主题 | 官方 URL |
|---|---|
| 安装前提 | `https://guide.cryosparc.com/setup-configuration-and-management/cryosparc-installation-prerequisites` |
| 安装步骤 | `https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/downloading-and-installing-cryosparc` |
| 硬件和系统要求 | `https://guide.cryosparc.com/setup-configuration-and-management/hardware-and-system-requirements` |
| v5.0 环境变量 | `https://guide.cryosparc.com/setup-configuration-and-management/management-and-monitoring-v5.0/environment-variables-v5.0` |
| cluster 配置示例 | `https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/cryosparc-cluster-integration-script-examples` |
| 访问 CryoSPARC | `https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/accessing-cryosparc` |

### 官方事实

- v5.0+ requires NVIDIA driver `570.26 or newer`；系统不需要另装 CUDA，CryoSPARC bundled CUDA 12.8，支持 compute capability 5.0 到 12.0。
- master 和 worker 应使用同一非特权 Unix account 及相同 numeric UID；普通 worker 由 master 通过 passwordless SSH 执行，cluster worker 由外部 scheduler（例如 SLURM、SGE、PBS）提交。
- 所有节点应通过 shared filesystem 以相同绝对路径访问安装和项目目录，项目 filesystem 需要支持 symlink；master 还需能访问 `https://get.cryosparc.com/` 完成 license/update 请求。
- base port `61000` 对应十个连续端口：`61000` Web、`61001` Mongo、`61002` REST API、`61003` Vis、`61004` Redis、`61005` Supervisor、`61006` app API，`61007-61009` reserved；worker 至少需要访问其中的 Mongo、Redis 及版本相关 API 端口。
- v5.0+ requires GLIBC `>=2.28`；官方列出的最低系统包括 Rocky/RHEL 8 和 Ubuntu 20.04，推荐 Ubuntu 22.04/24.04 或 Rocky 8/9/10。安装目录不能移动，real path 长度不应超过 83 个字符；master 和 worker 包合计至少需要 15GB。
- 官方 standalone 命令包含 `--standalone --license --worker_path --ssdpath --initial_email --initial_username --initial_firstname --initial_lastname`，可选 `--port` 和 `--initial_password`；master-only 命令使用 `--license --hostname --dbpath --port`，可选 `--insecure`、`--allowroot` 和 `--yes`。worker 安装后再执行 `cryosparcw connect`。
- cluster 连接从当前目录读取 `cluster_info.json` 和 `cluster_script.sh`，注册内容写入数据库，后续作业从数据库读取；同名 cluster 会覆盖原记录。required fields 是 `name`、`worker_bin_path`、`send_cmd_tpl`、`qsub_cmd_tpl`、`qstat_cmd_tpl`、`qdel_cmd_tpl`、`qinfo_cmd_tpl`，cache 相关字段可选。
- cluster scheduler 负责 CPU、RAM、GPU 数量和 GPU index 的分配，通常通过 GRES/cgroup 隔离；CryoSPARC worker 从 device 0 起使用。官方 SLURM 示例使用 `sbatch {{ script_path_abs }}`、`#SBATCH --cpus-per-task={{ num_cpu }}`、`--gres=gpu:{{ num_gpu }}`、`--mem={{ ram_gb|int }}G` 和 `{{ run_cmd }}`。
- 官方环境变量页面说明：修改 master `config.sh` 后需要 `cryosparcm restart`，修改 worker config 不需要 restart。主要默认值包括 `CRYOSPARC_API_PROCS=3`、`CRYOSPARC_CLUSTER_JOB_MONITOR_INTERVAL=10`、`CRYOSPARC_DB_CONNECTION_TIMEOUT_MS=20000`、`CRYOSPARC_DB_ENABLE_AUTH=true`、`CRYOSPARC_HEARTBEAT_SECONDS=180`、`CRYOSPARC_IGNORE_PORT_CONFLICTS=false`、`CRYOSPARC_INSECURE=false`、`CRYOSPARC_MONGO_CACHE_GB=4` 和 `CRYOSPARC_SSD_CACHE_LIFETIME_DAYS=30`。

### 官方页面的版本措辞冲突

安装页的一处旧段落仍写 worker driver `520.61.05`，而 v5.0+ prerequisites 页面和当前 master update 输出均要求 `570.26`。本报告按 v5.0+ prerequisites 和当前包实现采用 `570.26`，不能把旧段落当成当前最低版本。

## 环境变量核验清单

以下是本轮从源码确认、且与本生命周期直接相关的变量；不是整个 CryoSPARC 软件的完整环境变量全集。

| 变量 | 定义/来源 | 读取或传递位置 | 默认/作用域 |
|---|---|---|---|
| `CRYOSPARC_BUILD_LICENSE_ID` | 根目录 `build-workstation-podman.sh:161-164` 转成 Docker build arg | Dockerfile `:61-62`，传给安装器 `--license` | 零 UUID；仅 build-time，真实值不得提交 |
| `CRYOSPARC_LICENSE_ID` | 安装参数、容器运行 `-e`、runtime license file | master/worker `config.sh`、CLI、supervisor、cluster script | 安装时必须提供；容器从 `~/.cryosparc/license_id` 保存/恢复；贯穿 master、worker、API auth 和 cluster job |
| `CRYOSPARC_INSTALL_ROOT` | Dockerfile `:131-135` 或 wrapper default | 容器 wrapper 定位 master/worker | `/opt/cryosparc`；容器进程级路径根 |
| `CRYOSPARC_HOME` | 容器 `cryosparc:22-32` | license、DB、runtime config、init marker | `${HOME}/.cryosparc`；容器持久化边界 |
| `HOME` | 容器 run 显式传入或进程环境 | 容器 wrapper | 必须设置；影响 `CRYOSPARC_HOME` 与 projects path |
| `CRYOSPARC_BASE_PORT` | master install `--port` 写入 config；容器可由 request/runtime 覆盖 | `CoreSettings`、supervisor service ports、容器 API/Web 探测 | `61000`；`+1` Mongo、`+2` API、`+3` command_vis、`+4` Redis、`+5` supervisor、`+6` legacy app、`+9` debug |
| `CRYOSPARC_MASTER_HOSTNAME` | install `--hostname` 或容器自动探测 | hostname safety check、CoreSettings、API URL、worker/cluster connect | master install 默认 `hostname -f`；容器有 cluster 文件时优先可达 IPv4，否则 hostname |
| `CRYOSPARC_MASTER_HOSTNAME_AUTO` | 容器 wrapper 生成并写 runtime config | 后续 hostname 选择逻辑 | `false`/自动探测标记；容器内部运行时辅助状态 |
| `CRYOSPARC_WORKER_NAME` | 容器环境或 wrapper 自动设置 | local worker runtime config、worker connect | 容器 local worker 默认 `localhost`；仅 workstation/hybrid |
| `CRYOSPARC_WORKER_NAME_AUTO` | 容器 wrapper 生成 | local worker runtime config | 自动命名标记 |
| `CRYOSPARC_DB_PATH` | master install `--dbpath` 写 config；容器 runtime 默认 `${CRYOSPARC_HOME}/cryosparc_database` | CoreSettings、Mongo supervisor command、disk check | 安装器默认 master 目录上级 `cryosparc_database`；容器默认持久化 home 下 DB |
| `CRYOSPARC_CONFIG_DIR` | CLI 环境或容器 runtime config | `bin/cryosparcm` source config，CLI logging，supervisor | master 非容器默认安装根；容器为 `${CRYOSPARC_HOME}/master` |
| `CRYOSPARC_LOG_DIR` | CLI/容器 wrapper | supervisor 日志、CLI 日志、PID 迁移 | `${CRYOSPARC_CONFIG_DIR}/run` |
| `CRYOSPARC_FORCE_USER` | CLI default false；容器 wrapper 强制 true | owner safety check | 普通安装 false；容器因 `/opt/cryosparc` root-owned 而设 true |
| `CRYOSPARC_FORCE_HOSTNAME` | CLI default false；Dockerfile/container wrapper true | master hostname safety check | 普通安装 false；容器用于 hostname mismatch |
| `CRYOSPARC_LICENSE_SERVER_ADDR` | `bin/cryosparcm:136` | update/version/patch 相关网络请求 | `https://get.cryosparc.com` |
| `CRYOSPARC_DB_ENABLE_AUTH` | master installer `--disable_db_auth` 的反值 | `CoreSettings`、supervisor `--auth` flag、worker connect auth | true |
| `CRYOSPARC_INSECURE` | master installer `--insecure` | HTTP client/TLS 与 curl/update | false |
| `CRYOSPARC_SCRATCH_PATH` | 容器 wrapper | local worker `--ssdpath`、目录创建、reset 清理 | `/ssd` |
| `CRYOSPARC_SSD_RESERVE` | 容器 wrapper | local worker `--ssdreserve` | `768` MB |
| `CRYOSPARC_NOGPU` | 容器运行环境 | wrapper 触发 worker connect 的 `--no-gpu` | false；还会结合 `nvidia-smi` 探测 |
| `CRYOSPARC_WORKER_KEEPALL` | 容器运行环境 | `start` 是否清理非 cluster scheduler resources | 未设置时清理；设置后保留 |
| `CRYOSPARC_CLUSTER_ENABLED` | 容器运行环境 | 是否执行 `cryosparcm cluster connect` | true |
| `CRYOSPARC_WORKER_NOGPU` | 根构建脚本读取并传 Docker build arg | Dockerfile worker install 是否加 `--nogpu` | true；仅 build-time install 检查开关，不等同于 connect 的 `--no-gpu` |
| `CRYOSPARC_CLUSTER_HOSTS` | 根构建脚本 build arg | Dockerfile 写入 `/etc/hosts` | 默认 `12.12.4.3 login03 login03.szbl.hpc etcd_node`；build-time |
| `CRYOSPARC_START_SSHD` | entrypoint | 是否启动 SSH daemon | true；容器 entrypoint 作用域 |
| `CRYOSPARC_INITIAL_EMAIL` / `NAME` / `PASSWORD` / `USERNAME` | 容器 wrapper | `init` 首用户交互/非交互默认值 | email `hpc@szbl.ac.cn`、name `Cryo Sparc`、password `SZBL2026`、username 默认由 email 前缀生成 |
| `CRYOSPARC_ASSUME_YES` | 容器 wrapper | destructive reset 确认 | false |
| `CRYOSPARC_WARM_MASTER_FILES` / `CRYOSPARC_WARM_ROOT` | 容器 wrapper | init/start/restart 后台文件预热 | enabled by default；root 默认 master root |
| `CRYOSPARC_LANG` / `CRYOSPARC_LOCALE` | 容器 wrapper | 设置 `LANG`/`LC_ALL` | `en_US.UTF-8`；用于避免 Redis 因 locale 失败 |
| `CRYOSPARC_ENV_DIR` | master/worker CLI wrapper | Python env、`LD_PRELOAD` | master/worker 各自 `.pixi/envs/{master,worker}` |
| `PYTHONPATH` / `PYTHONNOUSERSITE` / `LD_PRELOAD` | master/worker CLI wrapper 或 `run_master_python` | Python CLI、supervisor、runtime helper | 防止外部 Python 包污染并固定 bundled Python |
| `MKL_NUM_THREADS` / `NUMEXPR_NUM_THREADS` / `OMP_NUM_THREADS` | master/worker CLI wrapper | CLI/Python/worker jobs | 默认 1，限制线性代数线程 |
| `NUMBA_CUDA_USE_NVIDIA_BINDING` / `NUMBA_CUDA_INCLUDE_PATH` / `NUMBA_CUDA_MAX_PENDING_DEALLOCS_COUNT` | worker CLI wrapper | worker GPU Python 进程 | 分别为 1、worker env include、0 |

## 包、容器和提交核验

### 当前安装包

- `pkg/cryosparc_master.tar.gz` 和 `pkg/cryosparc_worker.tar.gz` 的 `version` 均为 `v5.0.7`，`revision` 均为 `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`。
- `install-analysis.md` 中的 `v5.0.6`、旧 revision 和 patch `260710` 是历史分析，不能作为当前包版本依据；本轮保留该文件不改写，以免在没有对应 patch archive 的情况下伪造版本更新。
- `containers/cryosparc5/Dockerfile:43-125,127-171` 的 build-time master install 是非 standalone；`master` target 额外包含 cluster 配置，`workstation` target 包含本地 worker，`hybrid` target 同时包含本地 worker 和 cluster 配置。`master0` 只包含 master。
- `build-workstation-podman.sh:81-204` 只在显式 `--run` 时执行 Podman；默认 build license 是零 UUID，`CRYOSPARC_WORKER_NOGPU=true` 只控制 build-time worker `--nogpu`，不能替代运行时 connect 的 `--no-gpu`。
- 容器运行时由 `containers/cryosparc5/entrypoint:5-35` 启动 sshd 和 `/usr/local/bin/cryosparc`，再以 sleep loop 保持容器；容器的 `init` 才写 DB、license、首用户和 `.initialized`，这与旧的 build-time 预初始化模型不同。
- `containers/cryosparc5/cluster_info.json:2-13` 当前注册 name `szbl-cluster`、worker path `/lenovofs1/software/apps/cryosparc/5.0.7/cryosparc_worker/bin/cryosparcw`、SSH send command 和 SLURM `sbatch`；`cluster_script.sh:1-20` 用 `#SBATCH --gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}` 保证至少申请一块 GPU，并从 `${HOME}/.cryosparc/license_id`读取 license。

### 生命周期提交

| 提交 | 核验结论 |
|---|---|
| `a1a2bef01b8cbff9bb219cf87cd134904a8d8b19` | 将旧常驻 `run.sh` 改为 runtime `cryosparc-workstation` wrapper；移除 build-time 用户/DB 预初始化，由 `init` 负责首次初始化。 |
| `626f6d687b9975d6b7cc3bbf20c0f878c076ef94` | 增加 cluster license、cluster connect、环境和 reset 命令，并把 cluster GPU 申请模板接入运行时。 |
| `b3c37be483619fe4a9a872e388f0ddffbce0442c` | 将 cluster host 改为 build arg，调整最小 GPU 申请为至少一块，并对容器启用 `CRYOSPARC_FORCE_USER=true`。 |
| `8617eff20e6746c853d1247ae5446879fe16670a` | 引入 `master`、`workstation`、`hybrid` 三种镜像 target；它们是容器打包差异，不是 CryoSPARC 产品安装方式。 |
| `9e561fbb06259c35d687180d7063443acafbe6c3` | 启动时在没有完整 cluster 配置且未设置 `CRYOSPARC_WORKER_KEEPALL` 时清理旧 scheduler targets，再注册本地 worker。 |
| `8f8671509ca87860a889f5f0eaec266793aac4bc` | 在完整启动路径追加 `connect_cluster()`；已运行 fast path 不重复注册 cluster，cluster 配置变化后应显式 connect 或 restart。 |

## 调用链结论

- master shell `bin/cryosparcm` 读取 `config.sh` 并固定 bundled Python 环境，再 exec `cli/cryosparcm.py`；`CoreCommand` 在需要 Core 的 CLI 中启动 `core.startup("master")`，`ProtectedCommand` 负责 owner/hostname 安全检查。
- master `start` 的稳定顺序是 supervisor、Mongo、Redis/Core、instance startup/migrations、API、`PUT /start`、scheduler、command_vis、Web/app；supervisor 配置中的服务均 `autostart=false`，因此不能把 supervisord 启动误认为所有 CryoSPARC 服务已经启动。
- worker-side `cryosparcw connect` 启动 worker Core，检查 GPU/CPU/RAM/SSD，构造 node target，再通过 `find_or_add_lane` 和 `add_target` 写入 master scheduler；它不会启动 worker 常驻服务。
- master-side `cryosparcm worker connect` 则通过 `resources.connect_node` 组装 worker `connect` 参数，并经 SSH/target 执行远端 `bin/cryosparcw connect`；`gpu=false` 时传 `--no-gpu`。
- `cryosparcm cluster connect` 从当前目录读取两个 cluster 文件，调用 `core.cluster.connect` 创建或更新 cluster lane/target；cluster 作业由 `qsub_cmd_tpl` 提交脚本，状态/删除由 qstat/qdel 模板处理，计算节点不运行普通 worker daemon。
- 因此“安装方式”应归纳为 standalone workstation 与 master/worker 分离两种；cluster 是分离式 master 上的 scheduler integration，不是第三种普通 worker 安装。容器的 `master`/`workstation`/`hybrid` 只是这两种产品拓扑的镜像组合。

## 已执行的证据命令/工具

- 图谱：`list_projects`、`index_status`、`get_graph_schema`、`search_graph`、`trace_path`、`get_code_snippet`、`check_index_coverage`。
- 文件定位：`Glob`，主要定位 `containers/cryosparc5/*`、master `install/`、`pkg/*`。
- 源码/文档读取：`Read`、`Grep`。
- Git：
  - `git status --short --branch`
  - `git log --oneline -10`
  - `git log --all --oneline --decorate -20 -- "containers/cryosparc5"`
  - `git log --all --oneline --decorate -20 -- "README.md" "install.md" "install-analysis.md"`
  - `git log --all --oneline --decorate -20 -- "build-workstation-podman.sh"`
- 归档只读检查：`tar -tzf "pkg/cryosparc_worker.tar.gz"`，以及 `tar -xOzf` 读取 worker 安装器和 `cryosparcw` 到 `/tmp` 后用 `Read` 查看；未解压到仓库。

### gpu14 运行态 smoke 验证

测试位置为 gpu14 的 `~/git/Container-CryoSPARC`，未使用已有镜像 tag，而是创建以下隔离镜像和容器：

- workstation 镜像 `localhost/cryosparc-workstation:smoke-20260902`，image ID `6ea870efc266f85fd9272883c422ee7373a57c7af9f208470c16de15664890ca`。
- hybrid 镜像 `localhost/cryosparc-hybrid:smoke-20260902`，image ID `28af2fb3940c7ab714c2ba67c802ce5aaa2bd0cdd962d1f930595fe0609ee871`。
- 两个容器使用独立的 `$HOME/.cache/cryosparc-*-20260902` runtime home，并分别映射到 host `127.0.0.1:61011` 和 `127.0.0.1:61012`，容器内部仍使用 base port `61000`；没有删除或覆盖已有容器、镜像和远端工作区变更。

gpu14 没有可用的 NVIDIA CDI 配置，因此 `--device nvidia.com/gpu=all` 的首次尝试失败，原始错误为 `setting up CDI devices: unresolvable CDI devices nvidia.com/gpu=all`。测试改用宿主 `/dev/nvidia0`、`/dev/nvidia1`、`/dev/nvidiactl`、`/dev/nvidia-uvm` 等 device，并只读挂载 `nvidia-smi`、NVML 和 `libcuda.so.1`；这只是该 rootless Podman 主机的测试注入方式，不是对生产部署参数的建议。

workstation smoke 结果：

- 入口完成 master Mongo、Redis、3 个 API、scheduler、command_vis、app 和 app_api 启动，创建默认测试用户并注册 local worker；容器状态为 `running`，`cryosparc status` 的九个服务均为 `RUNNING`。
- HTTP `GET http://127.0.0.1:61011/` 返回 `200`。
- 容器内 `nvidia-smi` 检出两张 Tesla V100-PCIE-32GB，driver `580.126.09`；bundled worker Python 的 Numba 检查返回 `cuda_available=True`、`device_count=2`。
- worker connect 输出确认 64 CPUs、512 GiB RAM、`/ssd` 512GB、GPU `0,1` 两张 V100；随后执行容器内 `cryosparc stop` 和 `cryosparc start`，服务恢复、清理 1 个旧 scheduler target 并再次成功注册同一 local worker。

hybrid smoke 结果：

- `hybrid` target 在同样的 direct-device 注入下保持 `running`，HTTP 映射为 `127.0.0.1:61012 -> 61000`，master 服务和两张 GPU worker 均成功启动。
- `init` 自动读取镜像内的 `cluster_info.json`/`cluster_script.sh`，输出 `Successfully added cluster szbl-cluster`，说明容器生命周期中的 `connect_cluster()` 和 cluster target 注册路径可运行。
- 本次没有执行 `sbatch`、真实 job monitor、跨主机 `ssh 12.12.4.3` 或真实 license 校验；cluster smoke 只证明配置读取和 DB 注册，不证明调度器、共享文件系统或远程 worker 可用。

master target smoke 结果：

- `master` target 构建成功，image ID 为 `72ae1e26187546afd6df5553d6e4e7da889985706e4f34c14a30a98f3363b334`；它不包含本地 worker，但包含当前镜像定义中的 cluster 配置。
- 新 runtime home 的 master 容器保持 `running`，映射 `127.0.0.1:61013 -> 61000`，HTTP 返回 `200`，九个 master 服务均为 `RUNNING`，并成功注册 `szbl-cluster`。

上述三种 target 的 build/runtime smoke 覆盖了当前 Dockerfile 的 `master`、`workstation` 和 `hybrid` 分支；没有把这些 target 名称误解成三种 CryoSPARC 产品安装方式。

测试专用容器使用 rootless 默认 user namespace，使 entrypoint 能启动 sshd，故日志中的 local SSH string 为 `root@localhost`；这不验证生产环境推荐的普通 Unix 用户/跨主机 passwordless SSH。之前用 `--userns=keep-id` 的测试会把容器用户显示为 `ubuntu`，并在 worker GPU connect 处因未挂载 `libcuda.so.1` 报 `ImportError: libcuda.so.1: cannot open shared object file`；补齐 driver library 挂载后测试通过。

## 遗留限制和风险

1. 当前图谱 generation 为 `2026-08-17T02:25:43Z`，且 lifecycle 文件存在 metadata changed/not tracked；已对最终引用路径直接读取源文件，但图谱结果不能作为全仓库完备性的证明。
2. worker 没有在仓库内展开；本报告的 worker 行号来自 `/tmp/cryosparc-worker-read` 的临时只读展开，后续若替换 worker archive，应重新核对版本和行号。
3. `ex/cryosparc_master/bin/cryosparcm:298-310` 的 update 下载 URL 写成 `"{$CRYOSPARC_LICENSE_SERVER_ADDR}/download_request/$mode"`，花括号会被当成 URL 字面量的一部分；本轮未执行在线 update，也没有改写未跟踪的安装包源文件，应由后续 upstream/patch 工作单独处理。
4. worker installer 的 `SSD`/`SSD_PATH` 分支是残留代码，当前有效的 SSD 路径、quota、reserve 配置发生在 `cryosparcw connect`；安装文档不应把这些参数当作 worker `install.sh` 的有效选项。
5. 当前容器 `start` 的 fast path 不会重新读取 cluster 文件；挂载或修改 cluster 配置后必须执行 `cryosparcm cluster connect` 或 restart，不能只依赖普通 `start`。
6. gpu14 smoke 已证明当前 `master`、`workstation` 和 `hybrid` 镜像可以启动并暴露 Web，后两者可以注册本地 GPU worker，workstation 在 stop/start 后可以恢复；但测试使用零 UUID license placeholder，未证明真实共享文件系统、跨主机 SSH、GPU isolation、真实 scheduler 模板或真实 CryoSPARC job 可以工作。根据仓库测试规则，也没有执行 live container 的 `reset data`/`reset all`。

## 本轮完成标准

- 已给出官方安装、系统要求、环境变量、worker connection、cluster configuration 的 URL，并将官方要求与源码推断分开。
- 已从 worker archive 读取安装器、依赖安装器和 `bin/cryosparcw`，保留准确归档路径、版本、revision 和关键行区间。
- 已核对 master `CoreCommand`、`ProtectedCommand`、worker connect、cluster connect、`resources.connect_node`、`core.cluster.connect` 的调用关系。
- 已审阅 workstation lifecycle、cluster settings、target images、stale resources 和 `connect_cluster` 相关提交。
- 已形成 standalone、master/worker 分离和 cluster integration 的对照，并说明 cluster 不是第三种普通 worker 安装。
- 仍剩真实 license 下的 CryoSPARC job、跨主机网络/SSH、shared filesystem、scheduler 提交/监控和 GPU isolation 验证；这些需要明确的 license、集群环境和不破坏现有数据的批准，不能由本次 smoke 或静态研究替代。
