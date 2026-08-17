# CryoSPARC 安装脚本与补丁分析

本文基于以下内容整理：

- `install.md`
- `ex/cryosparc_master` 和 `ex/cryosparc_worker`：安装包解压目录
- `patch/cryosparc_master` 和 `patch/cryosparc_worker`：补丁包解压目录
- `pkg/*.tar.gz`：原始安装包和补丁包

## 1. 结论先行

当前包实际对应两种安装模式：

1. `workstation`：master 和 worker 在同一台机器，由 master 安装脚本串联完成。
2. 分离模式：先安装 `master`，再在 GPU 节点安装 `worker`，最后用 `cryosparcw connect` 注册 worker。

`cluster`/Slurm 不是第三种独立安装脚本。它使用非 standalone 的 master 安装，然后通过 `cryosparcm cluster connect` 生成调度器脚本；计算节点上的 worker 不是常驻 daemon。

当前包版本和补丁信息：

| 项目 | 值 |
| --- | --- |
| master 版本 | `v5.0.6` |
| worker 版本 | `v5.0.6` |
| master/worker revision | `88bd10121e1f5cfe2a07b608e593f4f4fade7b1f` |
| 补丁版本 | `260710` |
| 补丁适用版本 | `v5.0.6` |

## 2. 安装入口和依赖

### 2.1 master 入口

`ex/cryosparc_master/install.sh` 只是包装器，实际执行：

```text
ex/cryosparc_master/install/install_master.sh
```

master 安装器负责：

- 校验 license、操作系统、CPU 架构、hostname 和端口范围。
- 创建数据库目录。
- 写入 `cryosparc_master/config.sh`。
- 安装 master 依赖。
- 将 `cryosparc_master/bin` 加入用户的 `.bashrc` 或 `.bash_profile`。
- 尝试检查并安装当前版本补丁。
- 在 standalone 模式下启动 master、创建首个用户、安装并连接本机 worker。

### 2.2 worker 入口

`ex/cryosparc_worker/install.sh` 实际执行：

```text
ex/cryosparc_worker/install/install_worker.sh
```

worker 安装器负责：

- 校验 license、操作系统和 CPU 架构。
- 默认检查 `nvidia-smi` 是否存在。
- 写入 `cryosparc_worker/config.sh`。
- 安装 worker 依赖。
- 不安装 MongoDB、Node.js，也不启动 master 服务。
- 安装完成后只提示用户执行 `cryosparcw connect`。

### 2.3 两侧依赖内容

依赖安装由 `install/install_deps.sh` 完成。它比较 `deps_hashes` 和 `deps_bundle_hashes` 中的 hash，只有 hash 变化或指定 `--force` 时才重新安装。

| 安装侧 | 安装内容 | 实际目录 |
| --- | --- | --- |
| master | Python 环境 | `.pixi/envs/master` |
| master | MongoDB 4.0.28 | `deps/external/mongodb` |
| worker | Python 环境 | `.pixi/envs/worker` |
| worker | Gctf 1.06 | `deps/external/gctf-1.06` |
| worker | ctffind 4.1.14 | `deps/external/ctffind-4.1.14` |

这些依赖已经打包在安装包内，安装脚本通常是解压或复制，不是现场从 PyPI、MongoDB 或 NVIDIA 下载。

## 3. 模式一：workstation / standalone

### 3.1 脚本调用链

```text
cryosparc_master/install.sh
  -> install/install_master.sh --standalone ...
      -> cryosparcm deps
      -> cryosparcm patch [--yes]
      -> cryosparcm start
      -> cryosparcm user create ...
      -> cd <worker_path>
      -> worker/install.sh --license ... --standalone
      -> bin/cryosparcw connect ...
```

### 3.2 master 阶段

`install_master.sh --standalone` 的实际工作顺序如下：

1. 解析参数。standalone 至少要求 `--worker_path`、`--initial_email`、`--initial_username`、`--initial_firstname` 和 `--initial_lastname`；没有 `--initial_password` 时会交互式读取并确认密码。
2. 检查 license、curl、Linux/macOS、x86_64、master hostname 和 `BASE_PORT` 到 `BASE_PORT+10` 的端口范围。
3. 创建数据库目录，默认是 master 目录的上级目录下的 `cryosparc_database`。
4. 覆盖写入 master 的 `config.sh`，包括 license、master hostname、数据库路径、base port、是否 insecure、数据库认证开关等。
5. 执行 `cryosparcm deps`，安装 master Python 环境和 MongoDB。
6. 执行 `cryosparcm env` 并导入环境变量。
7. 尝试执行 `cryosparcm patch`。没有补丁或补丁检查失败时，安装脚本会继续执行；因此构建镜像时可能会访问 license server。
8. 执行 `cryosparcm start` 启动 master 全部服务。
9. 用指定的初始用户参数创建第一个用户。

### 3.3 worker 阶段

master 阶段完成后，脚本进入 `--worker_path`：

1. 执行 worker 安装脚本，写入 worker 的 `config.sh`。
2. 安装 worker Python、Gctf 和 ctffind 依赖。
3. 执行：

   ```bash
   bin/cryosparcw connect \
     --worker <master_hostname> \
     --master <master_hostname> \
     --port <base_port> \
     [--ssdpath <path>]
   ```

4. `connect` 会连接 master，探测 CPU、内存和 GPU，生成本机 worker target，并将它登记到 master 的 scheduler lane。

standalone worker 脚本中的 `--standalone` 主要用于标记安装模式和显示设置；真正的启动、建用户和连接动作由外层 master 脚本完成。

### 3.4 workstation 需要的实际参数

`install.md` 中的 workstation 示例少了当前脚本实际要求的参数。按当前 `install_master.sh`，至少需要类似：

```bash
./cryosparc_master/install.sh \
  --license "$LICENSE_ID" \
  --standalone \
  --worker_path /opt/cryosparc/cryosparc_worker \
  --hostname cryosparc \
  --port 61000 \
  --dbpath /var/lib/cryosparc_database \
  --ssdpath /scratch/cryosparc \
  --initial_email admin@example.org \
  --initial_username admin \
  --initial_firstname Cryo \
  --initial_lastname SPARC \
  --initial_password "$INITIAL_PASSWORD" \
  --yes
```

注意：`--worker_path` 指向已经解压的 worker 安装目录，不是 worker 压缩包路径。master 安装包本身不包含 worker tarball。

## 4. 模式二：master/worker 分离

### 4.1 master 场景

master 使用非 standalone 安装：

```bash
./cryosparc_master/install.sh \
  --license "$LICENSE_ID" \
  --hostname master01 \
  --port 61000 \
  --dbpath /data/cryosparc_database \
  --yes
```

脚本工作内容：

- 执行 master 的系统检查、端口检查和 hostname 解析。
- 创建数据库目录。
- 写入 master `config.sh`。
- 解压 master Python 环境和 MongoDB。
- 尝试检查/安装补丁。
- 不启动 master，不创建初始用户，不安装 worker。
- 最后提示手工执行 `cryosparcm start`。

master 安装不要求 CUDA，也不执行 GPU 检测。它只需要能运行 Web、数据库、调度和命令服务。

### 4.2 worker 场景

在 GPU 节点解压 worker 包并执行：

```bash
./cryosparc_worker/install.sh \
  --license "$LICENSE_ID" \
  --yes
```

worker 安装脚本的工作内容：

- 检查系统和 `nvidia-smi`。
- `--nogpu` 时跳过安装阶段的 `nvidia-smi` 提示。
- 覆盖写入 worker `config.sh`，通常至少包含 `CRYOSPARC_LICENSE_ID`。
- 安装 worker Python、Gctf 和 ctffind。
- 不启动 supervisor，不启动 MongoDB、Redis、API、scheduler 或 Web app。

然后在 worker 节点执行连接：

```bash
bin/cryosparcw connect \
  --license "$LICENSE_ID" \
  --master master01 \
  --port 61000 \
  --worker gpu001 \
  --sshstr cryosparc@gpu001 \
  --cpus 32 \
  --ssdpath /scratch
```

连接阶段会：

1. 连接 master 的 API/数据库。
2. 检测或禁用 GPU。
3. 计算 CPU 和 RAM slot 数量。
4. 检查 SSD 路径并设置 cache quota/reserve。
5. 建立 worker target 和 lane，并把 worker 注册到 master。

master 需要能够通过 SSH 访问 worker。之后 job 运行时，master 会通过 worker 的 `bin/cryosparcw` 执行计算命令；worker 不需要长期运行一个独立 worker daemon。

### 4.3 cluster/Slurm 场景

按照 `install.md`，cluster 场景仍先安装一个非 standalone master，然后执行：

```bash
cryosparcm cluster connect
```

该命令生成 `cluster_info.json` 和 `cluster_script.sh`。后续作业通过 `sbatch`、PBS 等调度器启动，不应把 cluster worker 当作普通常驻 worker 安装来处理。

## 5. 补丁包分析

### 5.1 当前补丁内容

master 和 worker 补丁包的结构都包含：

```text
cryosparc_<mode>/version
cryosparc_<mode>/patch
cryosparc_<mode>/core/sessions.py
```

当前补丁：

- `version`: `v5.0.6`
- `patch`: `260710`
- `core/sessions.py`: 在查询条件中增加 `deleted: False` 和 `failed: False`

master 和 worker 的补丁源码改动相同。补丁不是完整安装包，也不包含依赖、MongoDB、Python 环境或服务启动脚本。

### 5.2 补丁应用过程

master 侧 `cryosparcm patch` 会：

1. 查询当前版本的最新补丁。
2. 下载 master 和 worker 两个补丁包，或使用本地已下载文件。
3. 校验补丁包中的 `version` 必须和当前安装版本一致。
4. 使用 `tar --strip-components=1 --overwrite` 覆盖安装目录中的文件。
5. 更新数据库中的 running patch 标记。
6. 尝试自动更新已登记的普通 worker；cluster worker 需要手工更新。
7. 如果服务器元数据标记需要重启，则提示重启 master。

手工安装命令：

```bash
# master
cp cryosparc_master_patch.tar.gz /opt/cryosparc/cryosparc_master/
cd /opt/cryosparc/cryosparc_master
bin/cryosparcm patch --install

# worker
cp cryosparc_worker_patch.tar.gz /opt/cryosparc/cryosparc_worker/
cd /opt/cryosparc/cryosparc_worker
bin/cryosparcw patch
```

直接执行 `bin/cryosparcw patch` 时，只会校验版本并覆盖 worker 文件，不会启动 worker 服务。

### 5.3 版本、安装包和补丁 URL

可以从代码看到 URL 的主机和部分路径，但不能仅靠本地补丁目录还原一次真实补丁下载 URL，因为补丁 ID 和补丁元数据由 license server 返回。

默认 license server 是：

```text
https://get.cryosparc.com
```

代码中能看到以下路径：

| 用途 | URL/路径 | 位置 |
| --- | --- | --- |
| 旧版直接下载示例 | `https://get.cryosparc.com/direct/<version>?license=<license>` | `install_master.sh` 注释 |
| 集成测试下载安装包 | `https://get.cryosparc.com/download/{mode}-{version}/{license_id}` | `cli/container_testing.py` |
| 查询可用版本 | `POST /versions/list` | `bin/cryosparcm` |
| 查询最新版本 | `POST /versions/latest` | `bin/cryosparcm` |
| 更新安装包下载 | `POST /download_request/{mode}` | `bin/cryosparcm` |
| 补丁下载 | `GET /patch_get/{patch_id}/{mode}` | `cli/update.py` |

补丁完整形式可表达为：

```text
https://get.cryosparc.com/patch_get/<server_returned_patch_id>/master
https://get.cryosparc.com/patch_get/<server_returned_patch_id>/worker
```

其中 `<server_returned_patch_id>` 不在 `patch/` 文件中。license、版本、当前 patch 和 `requires_restart` 等信息由服务端返回；本地只保留补丁文件本身。

实际获取补丁元数据的 curl 命令是按版本 GET，不是对 `/patch_check/` 直接 POST：

```bash
LICENSE_ID='你的 license ID'
VERSION='v5.0.6'

curl --fail --silent --show-error --get \
  --data-urlencode "license_id=${LICENSE_ID}" \
  "https://get.cryosparc.com/patch_check/${VERSION}"
```

返回结果中的 `id` 就是 `patch_id`。本次验证返回：

```json
{
  "id": "v5.0.6+260710",
  "name": "260710",
  "applies_to_release": "v5.0.6",
  "requires_restart": true
}
```

如果安装了 `jq`，可以提取并下载两个补丁包：

```bash
PATCH_JSON=$(curl --fail --silent --show-error --get \
  --data-urlencode "license_id=${LICENSE_ID}" \
  "https://get.cryosparc.com/patch_check/${VERSION}")
PATCH_ID=$(printf '%s' "$PATCH_JSON" | jq -r '.id')

for mode in master worker; do
  curl --fail --location \
    --get --data-urlencode "license_id=${LICENSE_ID}" \
    -o "cryosparc_${mode}_patch.tar.gz" \
    "https://get.cryosparc.com/patch_get/${PATCH_ID}/${mode}"
done
```

这里 `mode` 只能是：

- `master`：下载 `cryosparc_master_patch.tar.gz`
- `worker`：下载 `cryosparc_worker_patch.tar.gz`

`workstation`、`standalone` 不是补丁下载的 mode。当前接口要求 URL path 中的 `+` 保持为字面量，例如 `v5.0.6+260710`；`license_id` 则通过 query 参数传递并由 `--data-urlencode` 编码。

另外，当前 `bin/cryosparcm` 的更新下载代码中实际写成了：

```text
{$CRYOSPARC_LICENSE_SERVER_ADDR}/download_request/$mode
```

这会保留字面量花括号，按 shell 展开后可能形成无效 URL。`/download_request/{mode}` 是代码意图，但在线更新功能需要现场验证；它不影响使用已经存在的 `pkg/*.tar.gz` 做离线镜像。

## 6. GPU 检测能否跳过

要区分“安装阶段提示”和“connect 阶段实际检测”。

### 6.1 master

可以完全没有 GPU。master 安装脚本不检测 CUDA，也不需要 NVIDIA driver。

### 6.2 worker 安装阶段

```bash
./install.sh --license "$LICENSE_ID" --nogpu
```

这里的 `--nogpu` 只跳过 `nvidia-smi` 检查。当前脚本即使不加 `--nogpu`，找不到 `nvidia-smi` 也只是 warning，不会因为这个检查直接退出。

### 6.3 worker connect 阶段

真正的 GPU 枚举发生在 `cryosparcw connect`。当前 CLI 支持：

```bash
bin/cryosparcw connect \
  --license "$LICENSE_ID" \
  --master master01 \
  --port 61000 \
  --worker gpu001 \
  --no-gpu
```

`--no-gpu` 会让连接逻辑跳过 driver/GPU 信息读取，并以 CPU-only worker 注册。旧的 `--nogpu` connect 选项仍存在，但已经标记为 deprecated。

### 6.4 workstation 的特殊点

原始 standalone 外层脚本最后固定执行：

```bash
bin/cryosparcw connect --worker "$MASTER_HOSTNAME" \
  --master "$MASTER_HOSTNAME" --port "$BASE_PORT" ...
```

但当前仓库的 `containers/workstation/cryosparc-workstation` wrapper 会在
`CRYOSPARC_NOGPU=true`、`nvidia-smi` 不存在或 GPU 查询失败时自动追加
`--no-gpu`。因此：

- GPU workstation：直接使用默认自动连接。
- CPU-only workstation：自动连接使用 `--no-gpu`，不会登记为 GPU worker。
- 如果绕过 wrapper 直接执行 `cryosparcw connect`，仍应显式传入 `--no-gpu`。

跳过 GPU 后，该 worker 不会被登记为 GPU worker，GPU 计算任务不能调度到它。

## 7. 服务启动顺序

### 7.1 推荐做法

不要直接手工启动 `mongod`、`redis-server`、`uvicorn` 和 Node。使用：

```bash
cd /opt/cryosparc/cryosparc_master
source config.sh
export PATH="$PWD/bin:$PATH"
eval "$(bin/cryosparcm env)"
bin/cryosparcm start
```

`cryosparcm start` 内部的实际顺序是：

1. 检查数据库剩余空间和端口冲突。
2. 启动 `supervisord`。
3. 启动 MongoDB `database`，并检查数据库。
4. 启动 Redis `cache`，等待 cache 连接，然后执行 core startup。
5. 启动 `api`，等待 API 端口，并调用 `PUT /start` 完成 API startup/migration。
6. 启动 `scheduler`。
7. 启动 `command_vis`。
8. 启动 Web app `app`。
9. 启动 legacy/live API `app_api`。

`config/supervisord.conf` 中这些服务全部是 `autostart=false`，因此顺序由 `cryosparcm start` 显式控制。

如果要把它写进 entrypoint，master 的业务顺序应保持为：

```bash
source /opt/cryosparc/cryosparc_master/config.sh
export PATH="/opt/cryosparc/cryosparc_master/bin:$PATH"
eval "$(/opt/cryosparc/cryosparc_master/bin/cryosparcm env)"
/opt/cryosparc/cryosparc_master/bin/cryosparcm start
# standalone 另行执行 user create 和 cryosparcw connect
```

不建议把 `mongod`、Redis、API、scheduler 和 Node 进程拆成任意顺序的裸命令；其中 API startup 依赖数据库、cache 和 core startup 已完成。

### 7.2 分离模式启动顺序

master 节点：

```bash
bin/cryosparcm start
```

worker 节点：

```bash
bin/cryosparcw connect \
  --license "$LICENSE_ID" \
  --master master01 \
  --port 61000 \
  --worker gpu001 \
  --sshstr cryosparc@gpu001 \
  --ssdpath /scratch
```

worker 节点没有同等的常驻服务启动顺序；它只需要安装目录、配置文件、依赖和能被 master SSH 执行的 `cryosparcw`。

### 7.3 workstation 启动顺序

完整顺序是：

```text
master install/config/deps
  -> optional patch check
  -> cryosparcm start
  -> initial user create
  -> worker install/config/deps
  -> cryosparcw connect
```

## 8. Docker workstation 优先建议

### 8.1 镜像构建时应使用本地包

优先使用已经存在的：

```text
pkg/cryosparc_master.tar.gz
pkg/cryosparc_worker.tar.gz
```

构建时不需要访问安装包下载 URL，也不需要重新下载 Python、MongoDB 或 worker 外部工具。补丁包应作为独立层或运行时文件处理，不建议在基础镜像中无条件执行在线 patch。

### 8.2 建议的固定布局

```text
/opt/cryosparc/cryosparc_master
/opt/cryosparc/cryosparc_worker
/var/lib/cryosparc_database
/data/cryosparc_projects
/scratch/cryosparc
```

安装目录不能随意移动；数据库、项目数据和 SSD cache 应使用 Docker volume。`install_master.sh` 的 `--worker_path` 应指向固定的 worker 目录。

master 安装器会用 `getent hosts <hostname>` 验证 `--hostname`。容器内应使用能在容器自身 `/etc/hosts` 或 DNS 中解析的固定 hostname，否则安装会在服务启动前退出。

### 8.3 构建时的系统依赖

当前脚本会使用或检查：

- `bash`
- `curl`
- `tar`
- `ss`，通常来自 `iproute2`
- `getent`，通常来自 `libc`/`netbase` 相关包
- x86_64 Linux

安装应使用非 root 的固定用户执行；如果必须用 root，需要显式加 `--allowroot`，但脚本本身明确不推荐这样做。

### 8.4 GPU 容器边界

NVIDIA driver 不应在普通 Docker 镜像内安装，driver 来自宿主机和 NVIDIA Container Toolkit。需要 GPU 的 workstation 容器运行时提供 `--gpus all`；当前仓库的 workstation wrapper 会为 CPU-only 环境自动执行带 `--no-gpu` 的 connect，绕过 wrapper 时才需要手工传入该参数。

### 8.5 容器进程问题

`supervisord.conf` 设置了 `nodaemon=false`。因此直接在 Docker `CMD` 中执行 `cryosparcm start` 后，shell 可能退出，容器也会退出。镜像入口点需要让一个前台进程持续作为 PID 1，或者使用外部进程监督方式保持 supervisord/容器运行。

## 9. 需要特别注意的不一致

当前 `install.md` 是概念和官方文档式说明，不完全等于当前 `v5.0.6` 安装脚本的可执行参数：

- workstation 示例没有 `--worker_path`，当前 standalone 脚本会因此退出。
- workstation 示例没有初始用户参数，当前脚本会要求交互输入或退出。
- `install.md` 把 `--ssdpath`/`--nossd` 作为安装参数描述；当前实现主要在 `cryosparcw connect` 阶段处理 SSD。
- worker 安装脚本的 `--nogpu` 是安装阶段检查开关；connect 阶段应使用 `--no-gpu`。
- `cryosparcm start` 实际启动的是 supervisor 管理的多个服务，不是单个进程。
- 补丁下载的 host 和部分 endpoint 可见，但 patch ID、补丁检查请求和认证细节部分位于已编译的 `licensing.cpython-312-x86_64-linux-gnu.so` 或由服务端返回，不能从 `patch/` 目录单独推导。
