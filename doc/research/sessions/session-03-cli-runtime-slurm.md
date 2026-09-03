# Session 03：CLI、生命周期与 Slurm

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_ff277cf7fffe3gFpWyVwkSlZwd` |
| 标题 | 更新默认密码与 CLI 默认值提示 |
| 时间 | 2026-08-17 02:23:44 至 2026-08-26 09:19:09 UTC |
| 规模 | 633 messages，3621 parts，257 text parts |
| 审计状态 | 可见记录充分；命令输出按关键路径和错误摘要。 |

初始 user 锚点为 `prt_00d8830d1001RRoDDUyvw40Ufy`。主题从 CLI 默认值扩展到容器 lifecycle、cluster connect、GPU 资源和 scheduler 卡死。

## 已核实结果

- 容器 wrapper 的 `test` 路径不加载安装配置、不启动服务、不修改数据库、license 或 runtime 目录；使用不存在的安装根路径做过验证。
- 默认值提示、readline、用户信息显示和后台 master 文件 warmup 已写入当前 `containers/cryosparc5/cryosparc`。
- `/opt/cryosparc` 被设置为容器运行用户可写，数据库默认位于 `~/.cryosparc/cryosparc_database`，scratch 默认 `/ssd`，SSD reserve 默认 `768 MB`。
- master 与 worker release 必须一致；旧记录中的 v5.0.6 worker 不能作为 v5.0.7 master 的默认 worker。
- `cryosparcm cluster connect --info .../cluster_info.json --script .../cluster_script.sh` 是正确的 cluster 注册入口，且需要先加载 runtime `CRYOSPARC_CONFIG_DIR`。
- `CRYOSPARC_FORCE_USER=true` 是容器 owner check 的适配，不是 master IP 修复；普通非容器安装应保持默认 false。
- Slurm 模板不能假设永远单 GPU。已观察到一 GPU/两 GPU 请求分别对应 `CUDA_VISIBLE_DEVICES=0` 和 `0,1`，CPU 数量按分区 GPU 默认值变化。
- scheduler 启动时反复查询失效 job `P2-J1`/`783845`，日志为 `slurm_load_jobs error: Invalid job id specified`，重试 97 次造成服务启动假性卡死。
- worker 运行时的 `pymongo.errors.OperationFailure: AuthenticationFailed` 与 worker 使用错误 license/config 的实验相符；共享 license file 和 cluster script 导出是修复方向。

## 直接来源

- `README.md:93-145` 记录当前 lifecycle、默认值、`CRYOSPARC_FORCE_USER`、GPU 和 reset 行为。
- `install-analysis.md:362-485` 记录 GPU 开关和服务顺序。
- `containers/cryosparc5/cluster_script.sh:2-20` 记录至少一块 GPU、license file 和 `{{ run_cmd }}`。
- `containers/cryosparc5/cluster-adaptation.md:157-232` 记录 Slurm 作业文件、GRES 和多 GPU验证。
- `containers/cryosparc5/cryosparc:511-564,734-797` 记录 worker/cluster connect、init、start、restart。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_00d8830d1001RRoDDUyvw40Ufy` | user，2026-08-17 | 默认值、CLI 和密码提示目标。 |
| `prt_0374617a6001U63EgkxNZlEw8t` | assistant，2026-08-25 | 失效 Slurm job 导致 scheduler 重试分析。 |
| `prt_03802e33c001DxWg4n6E5IkxLn` | assistant，2026-08-25 | GPU/Multi-GPU 和 CPU 资源结论。 |
| `prt_038099006001bPoxyubFkjTg50` | assistant，2026-08-25 | cluster 模板不能固定一 GPU 的结论。 |
| `prt_03d5d72fe001aDzIZTT5yYjcoO` | assistant，2026-08-26 | cluster runtime 修复提交总结。 |

## 完整性与限制

- `direct-source` 和 `runtime-observation` 足以支持当前 wrapper、模板和已记录 Slurm 作业的结论。
- `inference`：scheduler 卡死的直接触发点是 stale job 查询；更底层的 stale state 产生原因未在本 session 中完全追溯。
- `unresolved`：没有以真实 license 提交新作业，也没有把所有历史 job 的 scheduler 行为推广到其他 cluster lane。
