# 实验与验证记录

本文件汇总已有研究文档中的可复查实验，不把 dry-run、smoke 和生产作业混为一类。
容器和调度器参数的通用语义见[官方来源登记](../../official-sources.md#调度器和容器引擎官方资料)。

## 结果矩阵

| 实验 | 类型 | 结果 | 未覆盖内容 |
| --- | --- | --- | --- |
| gpu14 `localhost/cryosparc-workstation:test3` | 远程 build/runtime | master、worker、服务、`61000` 和本地 worker 通过；无 GPU build 路径通过。 | 不是当前 n5；未证明跨主机 SSH 或真实 license。 |
| gpu14 三个 `smoke-20260902` targets | 隔离 build/runtime | `master`、`workstation`、`hybrid` 均构建并启动；HTTP `200`；hybrid/master 注册 cluster DB target。 | 未提交 `sbatch`，未验证远程 cluster worker。 |
| live workstation `61000`/外部端口 | 只读 HTTP | 内部约 1ms、外部约 20-30ms；静态资源、协议接口和登录 cookie 正常。 | prefix 代理仍不兼容 root-absolute 路径。 |
| n5 isolated `test` | 安全只读探针 | 输出 `test mode: no services, data, or license configuration will be changed`；无服务/业务挂载。 | 未运行默认入口、`init` 或 `start`。 |
| n5 Podman events | 时间受限只读查询 | 看到 n5 image 的 `pull`/本地 tag 事件；未得到 build/push provenance。 | events 流式命令超时，不能据此证明没有其他事件；仍需 build log 或 registry audit。 |
| h1 已有实例 | 只读 runtime | 观察到 CryoSPARC master/Web 进程；PID1 为 sshd；脚本 hash 对应 commit `8f86715...`。 | 无法从进程重建原始 start command。 |
| GridView job `787683` | 宿主侧只读 | `DC_ENTRYPOINT=/bin/sh`、`DC_CMD_ARG` 末尾为 sshd；完成 runtime command 和 mounts 取证。 | 该 command 未启动 CryoSPARC wrapper；服务来源未证实。 |
| Slurm jobs `784210`/`784223`/`784224` | 资源 smoke | 一 GPU、默认 CPU、两 GPU 的 GRES/cgroup 可见性通过。 | 不是 CryoSPARC 真实处理作业。 |
| `ADD --unpack=true` parser | 语法验证 | Podman 报不支持该 flag；当前 Dockerfile 使用普通 `ADD`。 | 未测所有 Podman/Docker 版本。 |
| multi-image archive | manifest/传输验证 | 修复后 archive 有三个 entries；旧单 entry archive 不可当作三镜像包。 | 未证明 registry push 权限或生产传输成功。 |

## 关键实验来源

- `containers/cuda-ssh/deployment-check.md:577-646` 记录早期 workstation build/smoke。
- `doc/cryosparc-lifecycle-progress.md:265-295` 记录当前三个 target 的隔离 build/runtime smoke。
- `containers/cryosparc5/live-test.md:175-218` 记录 live HTTP、登录和资源请求。
- `doc/gridview-progress.md:27-59` 记录 n5 隔离探针，`:157-198` 记录 h1，`:200-276` 记录 job `787683`。
- `containers/cryosparc5/cluster-adaptation.md:220-232` 记录 GPU/CPU 绑定和模板更新边界。
- `doc/research/sessions/session-06-add-archive-transfer.md` 记录 parser 和 manifest 实验。

## 安全与可重复性

- 真实 license 和密码不写入本目录；命令示例使用变量或零 UUID placeholder。
- n5 探针显式禁用网络、capability 和写层，避免 accidental service start。
- 远端 live/Slurm 取证只读，不使用 sudo，不提交新作业，不取消现有作业。
- 大型 package archive 和镜像没有在 macOS 全量构建；磁盘峰值、最终 digest 和 registry provenance仍需单独验证。
- 远程路径、hostname、端口和 image tag 都是当次环境值，不能硬编码为通用生产配置。
