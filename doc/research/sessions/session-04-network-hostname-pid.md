# Session 04：网络、Hostname 与 PID

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_fbf34f5a8ffeVmRjo46VLjtnyD` |
| 标题 | CryoSPARC Workstation 网卡识别错误排查 |
| 时间 | 2026-08-27 01:17:23 至 2026-08-28 09:47:32 UTC |
| 规模 | 399 messages，2523 parts，120 text parts |
| 审计状态 | 可见记录充分；远端输出按错误和关键实验结果摘要。 |

初始 user 锚点为 `prt_040dad44600161RWhAe7I7WT72`，目标是解释容器为何使用 `127.0.0.1`、`worker-0` 或错误 CIDR，并修复服务启动和 worker 连接。

## 已核实结果

- `worker-0` 是平台创建容器时提供的 hostname；不是当前 Dockerfile 默认值，也没有证据表明它来自 `/etc/hostname` mount。
- `CRYOSPARC_FORCE_HOSTNAME=true` 只绕过 hostname 一致性检查，不把 hostname 转成 IP。
- `cluster_info.json` 中 `send_cmd_tpl=ssh 12.12.4.3 {{ command }}` 只控制 master 到登录节点的 SSH 提交，不决定 Slurm job 的 `--master`。
- 有 cluster files 时，容器 wrapper 从默认路由 source IPv4 选择可达地址；显式纯 IPv4 可以覆盖自动选择。无 cluster files 时使用 hostname 语义。
- 把 `173.0.75.3/24` 写入 `CRYOSPARC_MASTER_HOSTNAME` 会使 socket bind 失败，上层可能误报 `Unable start database port 61001 is in use`；`TIME-WAIT` 不等于 `LISTEN`。
- 修正为纯 IPv4 后，Mongo、API、Redis、scheduler、Web 等服务恢复；单节点 Mongo 使用 `localhost:61001` 和 `directConnection=True`，不需要导出/导入数据库。
- 容器内 local worker 默认采用 `--worker localhost --sshstr user@localhost`；外部 cluster worker 仍由 cluster 配置管理。
- `NO_PROXY` 与 `no_proxy` 会合并，并追加动态 master host，避免内部 API/数据库请求走代理。
- 残留 supervisord PID 不能单独证明服务健康；当前 wrapper 还检查进程命令行和 API listener，并在必要时 restart。

## 直接来源

- `containers/cryosparc5/cluster-adaptation.md:7-36,77-155` 记录地址职责、动态 IPv4、Mongo 和 worker 注册。
- `containers/cryosparc5/cluster-adaptation.md:264-314` 记录 supervisor/PID、API listener 和 61001 bind 错误。
- `containers/cryosparc5/cryosparc:68-138` 记录 master address 选择顺序。
- `containers/cryosparc5/cryosparc:140-192` 记录 `NO_PROXY` 合并和 master host 注入。
- `containers/cryosparc5/cryosparc:372-445` 记录 supervisor 健康检查和启动重试。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_040dad44600161RWhAe7I7WT72` | user，2026-08-27 | NAT 地址、127.0.0.1 和 hostname 问题。 |
| `prt_040f05b4a0019QCh0zwAa4MclF` | assistant，2026-08-27 | Mongo/PID 与启动阻塞诊断。 |
| `prt_040fa411c001rMExwfwerJ3p1O` | assistant，2026-08-27 | 服务 listener 和旧 PID 处理。 |
| `prt_04145f767001nSDaYkcHLNsSFQ` | user，2026-08-27 | 错误 CIDR、61001 和 job.log 问题。 |
| `prt_047c42c8d001mGRMgFpjesSEsE` | assistant，2026-08-28 | NO_PROXY 和文档清理阶段结果。 |

## 完整性与限制

- `runtime-observation` 覆盖了指定容器、指定 job 文件和服务恢复路径。
- `inference`：默认路由 source IPv4 是当前网络环境的可达地址选择，但不能保证其他网络拓扑的 route 一定面向计算节点。
- `unresolved`：mDNS 在容器 bridge 内可工作，但跨 IB 网络不可达；不应据此设计生产 master discovery。
- `unresolved`：已有作业的 `queue_sub_script.sh` 会固化旧地址，修改 runtime config 不会自动更新历史作业。
