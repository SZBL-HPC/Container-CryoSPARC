# Slurm 与 Cluster 研究

CryoSPARC cluster 语义和 Slurm GRES/cgroup 的上游资料见[官方来源登记](../../official-sources.md#调度器和容器引擎官方资料)。

## 两套地址职责

`containers/cryosparc5/cluster_info.json:2-13` 中的 `send_cmd_tpl` 是 master 到登录节点的控制路径；`CRYOSPARC_MASTER_HOSTNAME` 是 worker/job 访问 CryoSPARC master 的数据路径。两者不能混为一个 hostname。

当前 cluster 文件的关键值为：

| 字段 | 值或作用 |
| --- | --- |
| `send_cmd_tpl` | `ssh 12.12.4.3 {{ command }}` |
| `qsub_cmd_tpl` | `sbatch {{ script_path_abs }}` |
| `qstat_cmd_tpl` | `squeue -j {{ cluster_job_id }}` |
| `qdel_cmd_tpl` | `scancel {{ cluster_job_id }}` |
| `qinfo_cmd_tpl` | `sinfo` |
| `name` | `szbl-cluster` |
| `worker_bin_path` | `/lenovofs1/software/apps/cryosparc/5.0.7/cryosparc_worker/bin/cryosparcw` |

`send_cmd_tpl` 只影响 `sbatch`、`squeue`、`scancel` 和 `sinfo` 的远端执行位置，不会替换作业脚本中的 `--master`。

## Master 地址

容器内 hostname 可能是平台注入的 `worker-0`，计算节点不一定能解析它。当前 wrapper 在存在 cluster files 时按以下顺序选择 master address：

1. 用 `ip -4 route get 1.1.1.1` 的 source IPv4。
2. 没有默认路由时取第一个 global IPv4。
3. 没有 `ip` 时使用 `hostname -I`。
4. 没有 IPv4 时才回退到 hostname。

实现位于 `containers/cryosparc5/cryosparc:68-138`。显式纯 IPv4 的 `CRYOSPARC_MASTER_HOSTNAME` 可以选择多网卡中的计算节点可达接口；带 CIDR 的值不是合法 hostname/address 输入。

已记录的错误包括：

```text
worker-0:61001: [Errno -2] Name or service not known
Unable start database port 61001 is in use
```

第一条表明计算节点无法解析平台 hostname。第二条可能是错误 CIDR 导致 socket bind 失败后的上层误报；`TIME-WAIT` 不等于端口有 `LISTEN` 进程。详见 `containers/cryosparc5/cluster-adaptation.md:77-114,264-314`。

## 作业模板与 license

`containers/cryosparc5/cluster_script.sh:2-20`：

- 设置作业目录和 project/job name。
- 用 `#SBATCH --gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}` 保证至少申请一块 GPU，并保留多 GPU 数量。
- 固定分区 `NV_4090D`。
- 从 `${HOME}/.cryosparc/license_id` 读取并导出 `CRYOSPARC_LICENSE_ID`。
- 最后执行 CryoSPARC 渲染的 `{{ run_cmd }}`。

模板不保存真实 license。共享 home 或等效路径必须让新计算节点能够读取该 license file；文件不存在或为空时脚本应在提交的 worker command 前退出。

## GRES 与多 GPU

当前记录确认：

- `NV_4090D` 按 GPU 默认提供 8 CPU 和 102400 MB 内存。
- `--gres=gpu:1` 的作业观察到 `CUDA_VISIBLE_DEVICES=0`、`SLURM_GPUS_ON_NODE=1` 和 8 CPU。
- `--gres=gpu:2` 的作业观察到 `CUDA_VISIBLE_DEVICES=0,1`、`SLURM_GPUS_ON_NODE=2` 和 16 CPU。
- `SLURM_JOB_GPUS` 是节点物理 GRES 编号，可能与进程内重映射的 `CUDA_VISIBLE_DEVICES` 不同。
- `cgroup.conf` 的 `ConstrainDevices=yes`、`ConstrainCores=yes` 和 `ConstrainRAMSpace=yes` 负责设备与资源隔离；不要在模板中手工覆盖 `CUDA_VISIBLE_DEVICES`。

资源证据和作业编号见 `containers/cryosparc5/live-test.md:113-173` 与 `containers/cryosparc5/cluster-adaptation.md:206-224`。

## Scheduler stale job

一次启动卡住的直接日志为：

```text
ssh 12.12.4.3 squeue -j 783845
slurm_load_jobs error: Invalid job id specified
```

旧 scheduler 对失效的 `P2-J1`/`783845` 重试 97 次，阻塞了后续 `app` 和 Web 启动。这个结论解释了当次启动现象，但没有证明 stale job 的产生原因，也不能把所有启动延迟归因于 Slurm。

## Cluster 注册时机

`cryosparcm cluster connect` 把两个 cluster 文件的内容写入数据库。当前 wrapper 的 `init` 和完整 `start` 路径会调用它，但已运行 fast path 不会重复读取模板。修改 `cluster_info.json` 或 `cluster_script.sh` 后，应显式重新执行 cluster connect，或先按文档完成 restart。已生成的 `queue_sub_script.sh` 也不会因为 runtime config 改变而自动重写。

## 远端启动链与边界

GridView/Slurm 外层链路见 `doc/research/gridview/README.md`。对已有作业 `787683`，宿主侧参数确认了 `--entrypoint /bin/sh`、runtime setup、NVIDIA/Slurm mounts 和 `/usr/sbin/sshd`；它没有调用 CryoSPARC wrapper。因此 cluster job 的“容器被创建”和“CryoSPARC worker/master 被启动”必须分成两个验证问题。

未执行新的作业提交、取消或远端服务 init；当前报告只使用已有作业和历史作业的只读记录。
