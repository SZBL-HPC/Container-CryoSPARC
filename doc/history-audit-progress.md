# 历史研究资料审计进度

## 审计范围

本文件记录截至 2026-09-02 已完成的只读审计结果。

审计读取了 OpenCode SQLite 数据库 `/Users/galaxy/.local/share/opencode/opencode.db`，没有读取或输出 `reasoningEncryptedContent`、真实 license、密码字段或完整敏感 prompt。

本次使用的六个 session ID 是：

- `ses_033cafe22ffehnbHxUeAmN8k56`
- `ses_02f70f697ffeFPDB8zEDHIjDTg`
- `ses_ff277cf7fffe3gFpWyVwkSlZwd`
- `ses_fbf34f5a8ffeVmRjo46VLjtnyD`
- `ses_fb18b76b5ffeLixGi3lM09OFOH`
- `ses_faaa2ee7cffec9klaXQdFeLd9q`

本次已创建 `doc/research` 和 `doc/findings` 分文件；除这些 `doc/` 文档外，没有提交或修改其他仓库文件。

正式文件入口：

- `doc/research/README.md`
- `doc/research/sessions/`
- `doc/research/gridview/README.md`
- `doc/research/cryosparc-install/README.md`
- `doc/research/slurm/README.md`
- `doc/research/experiments/README.md`
- `doc/findings/verified-facts.md`
- `doc/findings/inferences-and-open-questions.md`
- `doc/findings/doc-drift-and-gaps.md`

## 会话读取状态

### `ses_033cafe22ffehnbHxUeAmN8k56`

标题为“分析安装脚本与Docker镜像制作方案”，时间为 2026-08-04 09:57:33 至 2026-08-10 03:17:55 UTC，共 806 条 message、4558 个 part。

已读取全部 user text、主要 assistant text、tool 类型及关键工具输出；超大工具输出按关键命令和结论摘要。

主要主题是 CryoSPARC v5.0.6 workstation 镜像、安装脚本、GridView HTTP 前缀、离线构建、容器启动顺序和 live test。

已确认的关键结果：

- GridView 访问失败的根因不是 gzip，而是 `/ai-forward/<id>/` URL 前缀与 CryoSPARC 的 root-absolute `/assets/*`、`/api/*` 和 WebSocket 路径不兼容。
- 曾测试 nginx/gzip proxy；最终删除 GridView variant，改为建议使用无 URL prefix 的 socket 或独立端口转发。
- Web 资源内嵌在 master 的 `app/custom-server/dist/client`，没有发现 Google/CDN 依赖。
- 本地包可用于离线构建；license 改为运行时提供，构建使用全零占位值。
- rootless Podman smoke test 使用 `--userns=keep-id`，验证了 master services、local worker、scratch 和 Web port `61000`。
- 容器 entrypoint 负责 `sshd`、管理命令和保活；无参数管理流程为 `init/start/status`。
- 已记录 locale 缺失导致 Redis 启动失败、API 初次 `503` 属于 readiness race、symlink build context 不能越过 build context、以及 root-owned 不可读文件导致后台 warmup 中止等错误。

### `ses_02f70f697ffeFPDB8zEDHIjDTg`

标题为“分析安装脚本与Docker镜像制作方案 (fork #1)”，时间为 2026-08-05 06:14:22 至 2026-09-01 07:48:00 UTC，共 234 条 message、1587 个 part。

前段主要重复 session 1 的安装、部署和 GridView 研究；后段是 2026-09-01 对 `localhost/cryosparc-hybrid:n5` 的调查。

该会话在历史记录收尾时仍未形成完整平台运行结论；本轮随后对已有 h1 实例和 GridView 作业 `787683` 做了独立只读补证，但服务启动来源仍未确定。

已确认的关键结果：

- SSH config 第 37 行报错：`Bad configuration option: 10.68.247.43`；后续改用 `/dev/null` 直接连接 gpu14。
- gpu14 为 rootless Podman `5.4.2`，graphroot 为 `/home/galaxy/.local/share/containers/storage`。
- `localhost/cryosparc-hybrid:n5` 存在，image ID 前缀为 `67114eb...`，创建时间为 `2026-09-01 01:11:58 UTC`。
- 调查容器使用 `--entrypoint /bin/sh -c 'sleep 3600'`，没有 mounts、devices 或 capabilities；PID1 是 sleep shell，不是 CryoSPARC 或 sshd。
- 多次 GridView/Slurm 检索因 shell quoting、命令解释错误或 timeout 失败。

历史记录当时尚未独立确认 GridView 实际启动命令、平台注入的 mounts/ENV，以及 job `760362` 的 image push 来源；本轮已对已有 job `787683` 的实际 runtime 参数补充核验，但 `760362` lineage 和 n5 push provenance 仍不能由现有记录证明。

### `ses_ff277cf7fffe3gFpWyVwkSlZwd`

标题为“更新默认密码与 CLI 默认值提示”，时间为 2026-08-17 02:23:44 至 2026-08-26 09:19:09 UTC，共 633 条 message、3621 个 part。

已读取 user text、主要 assistant text、工具 inventory 和关键实验输出；属于可见记录充分、超大工具输出摘要的审计状态。

主要时间线和结果：

- 2026-08-17 完成 CLI 默认值、明文密码 prompt、隐藏 `cryosparc-workstation test`、readline/ANSI 交互、master 目录后台 warmup、license 信息即时显示和 `--nogpu` 到 `--no-gpu` 的运行时调整。
- `test` 模式不加载安装配置、不启动服务、不修改数据库、license 或 runtime 目录；已用 `CRYOSPARC_INSTALL_ROOT=/nonexistent ./containers/workstation/cryosparc-workstation test` 验证。
- `CRYOSPARC_WARM_MASTER_FILES=false` 可关闭后台 warmup；不可读的 root-owned 文件应跳过而不是终止扫描。
- 2026-08-21 将 `/opt/cryosparc` 设为运行用户可写，命令放入 `/usr/local/bin`，默认 scratch 改为 `/ssd`，并使用 `--ssdreserve 768`；reset 只清理 scratch 内容，不删除目录本身。
- 记录了 `performance_benchmark_data_v1.tar.gz`、`empiar_10025_subset_v1.tar` 和 `empiar_10305.tar.gz` 的测试数据来源。
- 2026-08-24 确认 master 与 worker release 必须一致，5.0.7 master 不应调用 5.0.6 worker；worker 应解压后用统一版本安装。
- 正确的 cluster connect 需要显式使用 `cryosparcm cluster connect --info .../cluster_info.json --script .../cluster_script.sh`，并先加载 runtime `CRYOSPARC_CONFIG_DIR`。
- `CRYOSPARC_FORCE_USER=true` 解决 root-owned `/opt/cryosparc` 与 mapped user 的权限问题，与 master IP 无关。
- Slurm 不能固定为一张 GPU；实测一 GPU 对应 8 CPU、两 GPU 对应 16 CPU，并设置 `CUDA_VISIBLE_DEVICES=0,1`。CPU-only `import_movies` 产生 `--gres=gpu:0` 是作业资源渲染结果。
- scheduler 反复查询失效 job `P2-J1`/783845，日志为 `slurm_load_jobs error: Invalid job id specified`，重试 97 次造成 start 假性卡死。
- `job.log` 中的 `pymongo.errors.OperationFailure: AuthenticationFailed` 与 worker 使用错误 license/config 有关；后续方向是使用共享 `~/.cryosparc/license_id` 并在 cluster script 中导出 license。

### `ses_fbf34f5a8ffeVmRjo46VLjtnyD`

标题为“CryoSPARC Workstation 网卡识别错误排查”，时间为 2026-08-27 01:17:23 至 2026-08-28 09:47:32 UTC，共 399 条 message、2523 个 part。

已读取可见 user/assistant/tool 记录、工具 inventory 和关键输出；超大输出按关键路径、错误和实验结果摘要。

主要结论：

- 残留的 supervisord PID 可能仍然存在，但服务全部停止，导致脚本错误跳过 `cryosparcm start`；不能只按 PID 判断 supervisor healthy。
- 修复使用 `/var/run/cryosparc-supervisord.pid`，并同时检查 PID、命令行是否为 supervisord、master root 和 API listener。
- `worker-0` 是 GridView/Slurm 创建容器时注入的 hostname，不是镜像默认值，也不是 `/etc/hostname` mount 的结果。
- `cluster_info.json` 的 `send_cmd_tpl=ssh 12.12.4.3` 只控制登录节点提交命令；作业的 `--master` 来自 `core.settings.master_hostname`。
- `CRYOSPARC_FORCE_HOSTNAME=true` 只绕过 hostname 一致性检查，不会把 hostname 转为 IP。
- 默认路由 source IPv4 可用于自动更新 master address；显式 `CRYOSPARC_MASTER_HOSTNAME` 优先。
- 将 `173.0.75.3/24` 写入 master hostname 会导致 socket bind 失败，上层误报 `Unable start database port 61001 is in use`；`TIME-WAIT` 不等于存在 `LISTEN` 进程。
- 新容器使用实际 source IP 后，61000-61006 服务、API 和 Web 均恢复；MongoDB 是单节点 `localhost:61001` 加 `directConnection=True`，不需要迁移 replica set。
- local worker 使用 `--worker localhost --sshstr user@localhost`；外部 cluster worker 仍由 cluster 配置管理。
- `NO_PROXY` 和 `no_proxy` 会被合并并加入动态 master host，避免代理导致内部访问失败。

该会话的根因证据包括 `worker-0:61001: [Errno -2] Name or service not known`、`ServerSelectionTimeoutError`、`Unable start database port 61001 is in use`，以及 Slurm `_dockerlist_785203` 中的 `ALIAS=worker-0`、实际 `IPADDR=173.0.71.3` 和 `/etc/hosts` mount。

### `ses_fb18b76b5ffeLixGi3lM09OFOH`

标题为“创建 master 与 workstation 两种 CryoSPARC 镜像”，时间为 2026-08-29 16:57:35 至 18:16:37 UTC，共 98 条 message、642 个 part。

已读取全部 user text、主要 assistant text、工具 inventory 和关键输出；用户明确要求只做静态检查和 Podman dry-run，不做完整本地构建。

主要结论：

- image stages 演化为 `master0` 公共基础、`master` cluster-only、`workstation` master+local worker、`hybrid` 同时包含 local worker 和 cluster 配置。
- `EXPOSE`、`ENTRYPOINT` 和 ENV 会从父 stage 继承，放在公共 `master0` 可避免重复。
- 旧设计中的 `both` 是历史命名；当前仓库使用 `hybrid` 表示包含 cluster 能力的 workstation 行为。
- CryoSPARC archive 和 compiled binaries 目标为 `linux/amd64`；ARM 主机需要 amd64 emulation。
- `bash -n`、`git diff --check`、Podman 参数检查和 build dry-run 通过，但没有完整镜像 build 或 runtime smoke test 证据。

### `ses_faaa2ee7cffec9klaXQdFeLd9q`

标题为“ADD --unpack=true”，时间为 2026-08-31 01:09:17 至 10:14:25 UTC，共 234 条 message、1480 个 part。

已读取全部 user text、主要 assistant text、工具 inventory 和关键输出；属于可见记录充分、无完整敏感 prompt 输出的审计状态。

主要结论：

- Podman 6.1.0 不支持 `ADD --unpack=true`，精确错误为 `ADD only supports --chmod=<permissions>, --chown=<uid:gid>, --checksum=<checksum>, --link, --keep-git-dir, and --exclude=<pattern> flags`。
- `ADD` 也没有 `--strip-components=1`；因此使用普通 tar `ADD` 和后续目录布局处理。
- 后续验证了 package/patch 可选 ARG、`COPY --exclude='pkg/*/**'`、`-t/--tags`、root updater rename 和三镜像传输流程。
- 初始 `podman save` 未使用 `--multi-image-archive`，导致 archive 只有一个 manifest entry；修复后 archive 约 14.97GB、包含三个 entries。旧 archive 虽大小相近但只有一个 entry，需要重生成。
- 这些结果主要是语法、dry-run、最小传输或参数验证，不是完整 CryoSPARC 全量 build 的证据。

## 仓库交叉核验

历史审计快照曾为 `main` 分支的 `e9b6e8a`；当前工作区 HEAD 为 `8f8671509ca8`。本轮只新增/修改 `doc/` 审计文档；原有未跟踪的 `ex/`、`pkg/` 及其他用户内容未处理。

当前研究文件路径为：

- `README.md`
- `install.md`
- `install-analysis.md`
- `containers/cryosparc5/cluster-adaptation.md`
- `containers/cryosparc5/live-test.md`
- `containers/cuda-ssh/deployment-check.md`

当前实现相关路径为：

- `containers/cryosparc5/Dockerfile`
- `containers/cryosparc5/cryosparc`
- `containers/cryosparc5/cryosparcm`
- `containers/cryosparc5/cryosparcw`
- `containers/cryosparc5/entrypoint`
- `containers/cryosparc5/cluster_info.json`
- `containers/cryosparc5/cluster_script.sh`
- `build-workstation-podman.sh`
- `transfer-workstation-images.sh`
- `update-packages.sh`

历史路径 `containers/workstation/` 已由提交 `db338f6` 重命名为 `containers/cryosparc5/`，文档路径由 `ec5ccda` 更新；会话中的旧路径必须在后续研究文件中显式映射到当前路径。

当前 `README.md` 记录 v5.0.6、`master`/`workstation`/`hybrid` targets、无预初始化 DB/user、runtime `~/.cryosparc`、scratch `/ssd`、base port `61000`、rootless `--userns=keep-id`、runtime license、Slurm 配置、ENV、reset、warmup 和 SSH 规则。

当前 `install.md` 记录 single workstation、分离 master/worker 和 HPC/Slurm 的官方概念、安装命令、cluster files、端口范围及共享 filesystem 要求。

当前 `install-analysis.md` 记录实际两种安装脚本模式：workstation/standalone 与分离 master/worker；Slurm 是非-standalone master 后的 `cryosparcm cluster connect`，并记录依赖、启动顺序、patch `260710`、`--nogpu`/`--no-gpu` 和脚本差异。

当前 `cluster-adaptation.md` 与 `live-test.md` 记录动态 IPv4、hostname 解析、local worker、Slurm GRES、端口、HTTP/API、测试数据和 live 容器实验。

当前 `deployment-check.md` 记录 GridView 两层镜像构建 lineage、job `760362`、Slurm 运行命令、平台 mounts/ENV/hostname/GPU 注入、Podman/GPFS 限制、Harbor pull/push 权限及 cuda-ssh 只是 SSH/GPU base 而不是 CryoSPARC 服务。

关键 git 历史已核验：`cf6dbec` workstation startup、`092fdea` entrypoint、`a1a2bef` lifecycle、`a764768` offline/no-patch build、`898ef19` Slurm target、`b3c37be` cluster runtime、`b399111` supervisor/PID/start、`907671e` master address detection、`2ac3272` start 时刷新地址、`e726520` local worker localhost、`286305c` NO_PROXY、`8617eff` master/workstation/hybrid、`fee0d7d` platform cleanup、`3cb0e94` updater root、`aa76a72` optional package、`d790bdf` filters/tags、`ee02c47` transfer helper、`78f7811` multi-image fix、`db338f6` rename、`ec5ccda` 文档路径、`e9b6e8a` empty tags。

审计过程中使用过的证据命令或等价操作包括：

- `sqlite3 -readonly /Users/galaxy/.local/share/opencode/opencode.db` 查询 `session`、`message`、`part`，按 `session_id,time_created,id` 排序，提取 `role`、`type`、`tool`、`state.status` 和非 reasoning 文本。
- `git status --short`、`git log --oneline`、`git show <commit>`、`git log --stat`。
- `bash -n`、`git diff --check`、Podman build 参数和 dry-run 检查。
- 已使用 codebase-memory 的 `list_projects`、`index_status`、`check_index_coverage` 作为辅助，但未把图谱当作未跟踪路径的完整证据。

图谱项目为 `CryoSPARC`，generation 为 `2026-08-17T02:25:43Z`，状态 ready；`containers/cryosparc5` 未跟踪，`ex/`、`pkg/` 存在 known gaps 或设计性排除，因此所有相关结论以直接源文件和会话记录为主。

## 去重事实状态

### 已有直接证据

- 历史 v5.0.6 镜像分析及当前 target、端口、runtime state、scratch 和 rootless 运行要求，见 `README.md` 及 `doc/research/cryosparc-install/README.md`；当前 package 版本另行标注为 v5.0.7。
- workstation/standalone 与分离 master/worker 是安装脚本层面的两种模式，Slurm cluster connect 是后续配置流程，见 `install-analysis.md` 与 `install.md`。
- GridView 的实际容器构建叠加了仓库 Dockerfile 之外的运行时字段；历史 `760362` 见 `containers/cuda-ssh/deployment-check.md`，已有 `787683` 的宿主侧参数见 `doc/gridview-progress.md:200-276`。
- GridView 平台注入 hostname、GPU、用户、mounts、sshd 和 Slurm job 环境；`787683` 的最终 command 明确覆盖 ENTRYPOINT 为 `/bin/sh` 并以 `/usr/sbin/sshd` 结束，但该记录不能证明 CryoSPARC 服务的启动来源。
- CryoSPARC root-absolute URL 与 GridView prefix 的不兼容、动态 master IPv4 及 `worker-0` 解析失败均有日志、脚本或 live 容器证据。
- Slurm GRES 会影响 GPU、CPU 和 `CUDA_VISIBLE_DEVICES`；CryoSPARC 不能被简单假设为永远单 GPU。
- session 6 的 `ADD --unpack=true` 不受当前 Podman 支持，有明确 parser 错误。

### 推断或需要限定的结论

- image history 可以说明构建层 lineage，但不能单独证明 GridView 当前生产实例的实际启动命令、完整 mounts、ENV 或 push provenance。
- `containers/cuda-ssh/deployment-check.md` 的 GridView 实验可以证明某次 job 的平台行为，不能自动推广到所有 GridView 版本或所有分区。
- 文档与脚本已经多次演化；旧会话中的 `containers/workstation`、`both`、旧 worker 版本和旧 scratch 路径不能直接视为当前实现。

### 未决事项

- `localhost/cryosparc-hybrid:n5` 的 image metadata 已完成独立只读验证，但其 build/push provenance 仍无法从本地 image inspect/history 还原。
- 已有 GridView 作业 `787683` 的宿主侧 `prepare_container`、参数文件、`_dockerlist`、`prolog.env` 和 `scontrol show job` 已完成只读取证；其最终 command 未调用 CryoSPARC wrapper，因此该作业的 CryoSPARC 服务启动来源仍未确认。
- 没有在 macOS 完成包含完整 CryoSPARC 包的全量镜像 build；许多构建结论来自静态检查、dry-run 或远程测试。
- 图谱未覆盖 `containers/cryosparc5`，且 `ex/`、`pkg/` 有未跟踪、known gap 或 deliberately excluded 内容，不能据此作穷举性负面结论。
- 部分会话工具输出因体积按摘要读取；后续若要发表逐条工具证据，应重新按时间窗口读取对应 SQLite 记录。

## 阻塞原因

- 2026-09-01 SSH config 第 37 行的 `Bad configuration option: 10.68.247.43` 阻碍了原 SSH alias 的使用。
- session 2 的远程命令存在 shell quoting 错误，部分命令在本地 zsh 中被解释，另有递归检索 timeout。
- GridView/Slurm 的实际运行环境依赖远端平台注入，不能仅靠仓库 Dockerfile 或静态 image history 还原。
- 完整包和镜像较大，当前已知验证主要是语法、dry-run、静态检查和有限的远程 smoke test。

## 本轮完成情况

- 已创建 `doc/research` 和 `doc/findings` 的正式分文件，并在每个 session 文件中记录目标、时间、规模、关键 part 锚点、证据等级和完整性限制。
- 已把六个 session、当前仓库文件、关键 Git commit、n5/h1 只读记录和已有 GridView job `787683` 汇总到专题报告与去重 findings。
- 已完成 n5 image metadata 和 GridView job runtime command 的独立只读核验；没有把 h1、历史 `760362` 或 image history 当作 n5 push provenance 的替代证据。
- 已整理关键 SQLite `part.id` 引用；大型 tool output 仍按摘要记录，逐字恢复需按 session/time window 重新查询。

## 仍未完成或不宜执行的验证

- n5 的原始 build context、commit、registry push 和 tag promotion provenance 仍未从现有 metadata 还原；本轮对 gpu14 做了时间受限的 `podman events` 只读查询，仅看到 pull/本地 tag 事件，因流式命令超时不能把未显示 build/push 事件解释为不存在。
- h1 中已运行 CryoSPARC 服务的启动者和启动时间仍没有独立审计记录；不能由 PID1 或进程列表反推。
- 未在 n5 中执行 `init`、`start` 或无参数入口，未提交新的 Slurm 作业，未使用真实 license 做跨主机端到端验证。
- 未在 macOS 完成包含完整 CryoSPARC package 的全量镜像 build；当前完整 smoke 证据来自 gpu14 的隔离 workspace，不能替代生产验证。
- 代码图谱 generation 为 `2026-08-17T02:25:43Z`，且 `containers/cryosparc5`、`ex/`、`pkg/` 存在覆盖限制；涉及这些路径时仍需直接读取 source/archive。

若继续 n5/GridView 调查，应只在用户授权的 OpenCode 数据目录和指定测试主机范围内，使用短命令读取已有平台日志、runtime metadata 和 registry audit；不要扫描整个 home、输出凭据、覆盖 n5 tag 或执行不必要的完整 pull/build。
