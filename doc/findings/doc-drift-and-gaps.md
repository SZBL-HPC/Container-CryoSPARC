# 文档漂移与覆盖缺口

## 路径与命名漂移

| 旧记录 | 当前状态 | 处理方式 |
| --- | --- | --- |
| `containers/workstation/` | 已由 commit `db338f6` 重命名为 `containers/cryosparc5/`。 | 新报告使用当前路径；引用历史 session 时保留旧路径并注明映射。 |
| `both` target | 已由 `hybrid` 取代。 | `hybrid` 表示同时含 local worker 和 cluster files 的镜像 target。 |
| `run.sh`/前台 workstation 启动 | 当前由 `entrypoint` + `/usr/local/bin/cryosparc` 管理。 | 不把旧前台行为当成当前 lifecycle。 |
| `$HOME/.cryosparc/master/run/supervisord.pid` | 当前 PID file 为 `/var/run/cryosparc-supervisord.pid`。 | 旧 PID 出现时先判断镜像是否过旧，不直接判断服务健康。 |

## 版本漂移

- `install-analysis.md:19-27` 的主版本为 v5.0.6、patch 为 260710；当前 package 在 `doc/cryosparc-lifecycle-progress.md:17,223-230` 核验为 v5.0.7、revision `dfcba2f3ac0fe600b22b97895e9ca25abbffcee7`。
- 历史 session 中的 v5.0.6 worker、旧 patch URL 结果和当前 v5.0.7 package 不应合并成一条版本事实。
- `cluster_info.json` 当前 worker path 是 v5.0.7；使用旧 worker path 时需要重新核对 master/worker revision 一致性。

## 网络和端口漂移

- `containers/cryosparc5/live-test.md:7-11` 仍记录特定 live 实例的 `40008` Web 和 `40002` SSH；`cluster-adaptation.md:19-20` 已说明外部端口随实例变化。
- 容器内部 `61000-61006` 是服务端口；NAT 外部端口、GridView container IP 和 `worker-0` 都是环境值，不能写入通用运行逻辑。
- `cluster_info.json` 的 `12.12.4.3` 是当前登录节点配置，不等于容器 master 的可达 IP，也不应由 `send_cmd_tpl` 推导 `--master`。

## 文档与实现差异

- `README.md:133` 说明 Dockerfile build-time 写入 `CRYOSPARC_CLUSTER_HOSTS`；这不是运行时 `/etc/hosts` 持久化保证，平台的 `/etc/hosts` bind mount 会覆盖它。
- `README.md:129-132`、`cluster-adaptation.md:226-232` 对 cluster connect 时机已有说明，但修改模板后若只执行普通 `start`，数据库中的旧 target 仍可能继续使用旧模板。
- `install-analysis.md` 仍是有价值的 v5.0.6 安装机制分析，但不能独立作为当前包版本、patch 状态或在线 URL 成功性的证明。
- `containers/cuda-ssh/deployment-check.md` 记录的是 SSH/GPU base 与历史 GridView import，不是 CryoSPARC master 镜像；其中的历史 runtime mounts、entrypoint 和 password/auth 行为不能直接套用当前 `cryosparc5`。

## 覆盖缺口

- Codebase Memory generation 为 `2026-08-17T02:25:43Z`，`containers/cryosparc5` 未跟踪，`ex/`/`pkg/` 存在 not tracked、metadata changed 或设计性排除；图谱结果不支持全仓库负面结论。
- worker 安装器没有以展开源码形式存在于当前工作区；相关行号来自 package archive 的临时只读展开，替换 archive 后必须重新核对。
- 大型 OpenCode tool output 在历史审计中按摘要读取；session 文件的 part ID 是上下文锚点，不保证每一条原始 shell 输出都已逐字保留。
- 没有在 macOS 完成完整 package image build，也没有用真实 license 做跨主机 worker 或 Slurm 端到端作业。
- GridView 平台脚本位于远端 `/opt/gridview/...`，不属于当前仓库；已有 job 记录能证明指定实例的参数，不能证明平台所有版本的默认行为。

## 安全与发布缺口

`containers/cuda-ssh/deployment-check.md:573-575` 报告历史 `cuda-ssh` Dockerfile 的固定 root password 会出现在 image history。该报告没有复制密码值；在任何公开发布或复用该镜像前，应重新审计当前 tag、轮换可能仍有效的凭据，并改为 runtime secret。这个风险不能从当前 CryoSPARC v5 wrapper 的 license 处理结论中消除。
