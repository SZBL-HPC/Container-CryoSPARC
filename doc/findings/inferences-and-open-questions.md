# 推断与未决问题

## 推断

| ID | 推断 | 置信度与依据 |
| --- | --- | --- |
| I-001 | GridView job `787683` 中 CryoSPARC 服务若确实存在，应来自该 `docker run` 之外的生命周期或此前过程，而不是记录中的最终 command。 | 高；command 明确覆盖 ENTRYPOINT 且未调用三个 CryoSPARC wrapper，但缺少完整进程启动审计。 |
| I-002 | n5 与当前 Dockerfile 的差异更像是不同构建 revision 或旧 wrapper 产物，而不是单凭 tag 可解释的 tag drift。 | 中；inspect/history 和当前 Dockerfile 不一致，但没有 registry push/build log。 |
| I-003 | 默认路由 source IPv4 是当前容器拓扑下最可能的计算节点可达 master 地址；多网卡或策略路由环境仍需显式选择。 | 高；wrapper 实现和 live 错误共同支持，但拓扑依赖明显。 |
| I-004 | `worker-0` 的解析失败与平台 shared hosts 注入、解析时机或不同 namespace 之一有关，不能只归因于 hosts 文件缺行。 | 中；shared hosts 有对应行，但 `sudo` 仍报解析失败，缺少失败进程的完整 namespace 证据。 |
| I-005 | scheduler 的 97 次 stale job 重试是当次 app/Web 未及时启动的直接触发因素，不一定是根本数据损坏原因。 | 高；日志明确显示失效 job 查询和重试；stale state 的产生过程未追溯。 |
| I-006 | build-time 追加 `/etc/hosts` 不能作为运行时服务发现机制，尤其是平台会覆盖 `/etc/hosts` 时。 | 高；Dockerfile 写入位于 build stage，n5 探针显示运行时 hosts 行为独立，平台 job 还会 bind mount shared hosts。 |

## 未决问题

| ID | 问题 | 当前状态与安全下一步 |
| --- | --- | --- |
| Q-001 | n5 是由哪个 build context、commit 和 push 操作产生的？ | `unresolved`；已对 gpu14 做时间受限的 `podman events` 只读查询，仅看到 pull/本地 tag 事件且查询流式超时；仍需授权的本地 build/push 记录或 registry audit，不能覆盖 n5 tag。 |
| Q-002 | h1 中的 supervisord 和 CryoSPARC 服务由谁启动？ | `unresolved`；需要已有实例的 audit log、父进程时间线或平台启动日志，不能凭 PID1 反推。 |
| Q-003 | 当前 GridView 版本是否总是覆盖 ENTRYPOINT 为 `/bin/sh`？ | `unresolved`；已有 `787683` 和历史 `760362` 支持该实例结论，不能推广到其他版本/分区。 |
| Q-004 | `worker-0` 解析失败发生在 sudo、登录 shell 还是应用进程的哪个 namespace？ | `unresolved`；若继续验证，只读取现有作业的 namespace、hosts 和 resolver 状态，不修改 shared hosts。 |
| Q-005 | 当前 v5.0.7 package 的在线 patch metadata 和完整 build 是否可重复？ | `unresolved`；现有 macOS 未做 full build，历史 v5.0.6 patch 不能替代 v5.0.7 验证。 |
| Q-006 | stale Slurm job 如何进入 scheduler state，是否需要启动前清理？ | `unresolved`；当前 wrapper 有非 cluster resource 清理路径，但需要单独的非生产 runtime fixture 验证。 |
| Q-007 | 图谱对 `containers/cryosparc5`、`ex/` 和 `pkg/` 的覆盖是否完整？ | `unresolved`；当前图谱 generation 较早且存在 not tracked/metadata changed；继续研究必须直接读 source/archive。 |

## 明确禁止的推断

- 不能把 image inspect 的 `ENTRYPOINT` 当成 GridView 实际执行命令。
- 不能把 h1 的运行进程当成 n5 的内容或 provenance。
- 不能把有一条 `worker-0` hosts 记录当成所有 namespace 都能解析该名称。
- 不能把一次 rootless smoke 当成真实 license、跨主机 SSH、shared filesystem 或 Slurm job 已通过。
- 不能把 `workstation`、`master`、`hybrid` target 当成三种 CryoSPARC 安装方式。
