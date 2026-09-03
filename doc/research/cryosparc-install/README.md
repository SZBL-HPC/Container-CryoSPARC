# CryoSPARC 安装与生命周期

产品安装前提、安装命令、v5.0 环境变量、cluster 模板和 UI 访问的官网链接统一见[官方来源登记](../../official-sources.md#cryosparc-官方资料)。

## 版本边界

`install-analysis.md` 主要分析的是 master/worker `v5.0.6` 与 patch `260710` 的历史安装材料。当前 `pkg/cryosparc_master.tar.gz` 和 `pkg/cryosparc_worker.tar.gz` 在 `doc/cryosparc-lifecycle-progress.md:223-230` 中核验为 `v5.0.7`，revision 为 `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`。

因此，v5.0.6 patch 结论不能直接当成当前 v5.0.7 包的 patch 状态；文件级安装机制可以复用，但版本值必须分别标注。

## 产品安装方式与镜像 target

产品安装方式只有两类：

| 安装方式 | master | worker | cluster |
| --- | --- | --- | --- |
| standalone workstation | `--standalone`，同机安装 | 同机安装并 `cryosparcw connect` | 不需要作为普通 worker 安装 |
| 分离式部署 | 非 standalone master | GPU 节点单独安装并 connect | master 上执行 `cryosparcm cluster connect`，计算节点由 scheduler 启动 |

仓库的 `master`、`workstation`、`hybrid` 是镜像内容 target，不是三种产品安装方式。当前定义见 `containers/cryosparc5/Dockerfile:127-171`。

## 脚本调用链

### Standalone

```text
cryosparc_master/install.sh
  -> install/install_master.sh --standalone
  -> cryosparcm deps
  -> optional cryosparcm patch
  -> cryosparcm start
  -> create initial user
  -> worker/install.sh --standalone
  -> cryosparcw connect
```

master 安装器负责 license、OS、架构、hostname、端口、数据库目录、`config.sh`、bundled dependencies 和首用户。worker 安装器负责 worker config 与 bundled Python/Gctf/ctffind，不启动 MongoDB 或 master 服务。调用链和参数要求见 `install-analysis.md:80-151`。

### 分离 master/worker

非 standalone master 安装会写 config、安装 master dependencies 和尝试 patch，但不启动 master、不创建首用户、不安装 worker。worker 节点单独安装后，通过 `cryosparcw connect --master ... --worker ... --sshstr ...` 注册。见 `install-analysis.md:153-219`。

### Cluster/Slurm

cluster 不是第三种普通 worker 安装方式。master 安装后读取 `cluster_info.json` 和 `cluster_script.sh`，执行 `cryosparcm cluster connect`，把 scheduler target 写入 CryoSPARC 数据库。后续作业由 `sbatch` 等模板提交，计算节点不运行常驻 worker daemon。见 `install-analysis.md:221-229` 和 `containers/cryosparc5/cluster_info.json:2-13`。

## 当前容器生命周期

`containers/cryosparc5/entrypoint:5-35` 启动 sshd，调用 `/usr/local/bin/cryosparc`，并用 sleep loop 保活。`containers/cryosparc5/cryosparc:734-797` 定义 `init`、`start`、`stop` 和 `restart`：

- `init` 收集用户值、读取或保存 license、写 runtime config、启动 core services、创建首用户、写 `.initialized`，再注册本地 worker 和 cluster。
- `start` 检查 initialized 状态，必要时刷新 master 地址和 `NO_PROXY`，启动服务，再注册 local worker 和 cluster。
- `stop` 只停止 CryoSPARC daemon，不删除 runtime home 或容器。
- `restart` 先 stop，再按 start 路径重新启动。

`start_core_services()` 的顺序是写 runtime config、创建 DB/scratch/projects、启动 master、等待 API、启动 `scheduler`、`command_vis`、`app`、`app_api`，最后等待 Web，见 `containers/cryosparc5/cryosparc:554-564`。

## License、patch 与 GPU

- 构建使用 `CRYOSPARC_BUILD_LICENSE_ID` 的零 UUID 默认值；真实 license 只在 runtime 由环境或 `~/.cryosparc/license_id` 提供，见 `containers/cryosparc5/Dockerfile:61-84` 和 `containers/cryosparc5/cryosparc:282-307`。
- v5.0.6 历史脚本中的 patch metadata 通过 `/patch_check/<version>` 查询，返回的 `id` 再用于 `/patch_get/<patch_id>/<mode>`；`mode` 是 `master` 或 `worker`，不是 `workstation`，见 `install-analysis.md:279-360`。
- worker 安装阶段的 `--nogpu` 只控制 `nvidia-smi` 检查；connect 阶段的 `--no-gpu` 才控制 worker 是否登记 GPU，见 `install-analysis.md:362-410`。
- 当前容器 wrapper 在没有 `nvidia-smi`、GPU 查询失败或设置 `CRYOSPARC_NOGPU=true` 时自动追加 `--no-gpu`，见 `containers/cryosparc5/cryosparc:511-539`。

## 构建与持久化边界

- Dockerfile 先解包 master，按 `CRYOSPARC_INCLUDE_WORKER` 选择 worker stage；patch archive 作为可选 build context 文件复制并在 installer stage 应用，见 `containers/cryosparc5/Dockerfile:47-125`。
- 构建时临时启动数据库和服务以完成安装/patch，随后删除 runtime marker、run 目录和临时 database；最终 image 不预初始化用户或业务数据库。
- runtime database、license、config、项目目录和 scratch 依赖外部 volume 或 bind mount；Dockerfile 没有声明 named VOLUME。
- `/opt/cryosparc` 在最终镜像中被设为运行用户可写，`/ssd` 和 `/var/run` 被创建并设置为可写，见 `containers/cryosparc5/Dockerfile:125-152`。

## 证据限制

当前生命周期研究已在 gpu14 完成隔离的三个 target smoke，但没有真实 license、跨主机普通 worker SSH 或真实 Slurm 作业验证，详见 `doc/cryosparc-lifecycle-progress.md:265-300`。因此“安装脚本做什么”和“本地容器能启动”是已分开的两种结论，不能把 smoke 结果推广为生产 cluster 可用性。
