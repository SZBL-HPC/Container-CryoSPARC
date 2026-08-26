# Workstation Live Test

记录 live workstation 的登录方式、访问测速方法和当前结论。

## Target

- Web URL：`http://10.68.247.45:40008/`
- SSH：`ssh -p 40002 xshu@10.68.247.45`
- 容器内 Web：`http://127.0.0.1:61000/`
- CryoSPARC：`v5.0.6+260710`
- SSH 容器重建后可能出现 host key changed 警告；不要因此修改应用配置。

## Login

CryoSPARC 前端不会把明文密码直接发送到 `/api/auth/login`。它会先计算密码的 SHA-256 小写十六进制字符串，然后使用 cookie 保存登录会话。

默认账号：

- Email：`hpc@szbl.ac.cn`
- Password：`SZBL2026`

```bash
COOKIE_FILE="${TMPDIR:-/tmp}/cryosparc-cookies.txt"
PASSWORD_HASH="$(printf '%s' 'SZBL2026' | shasum -a 256 | cut -d' ' -f1)"

curl --noproxy '*' -sS \
  -c "$COOKIE_FILE" \
  -X POST 'http://10.68.247.45:40008/api/auth/login' \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"hpc@szbl.ac.cn\",\"password\":\"$PASSWORD_HASH\"}"
```

登录后使用同一个 cookie 访问协议内容：

```bash
curl --noproxy '*' -sS \
  -b "$COOKIE_FILE" \
  'http://10.68.247.45:40008/api/utility/license'
```

协议接受状态由前端写入：

```text
PUT /api/cmd/users/%25CURRENT_USER%25/state/licenseAccepted
```

`/api/utility/agreement` 不是当前版本的协议接口；正确接口是 `/api/utility/license`。

## Test Data Downloads

`cryosparcm downloadtest` uses the following public object URLs through the
default `https://s3.wasabisys.com/` endpoint:

| Dataset | Command | Download URL |
| --- | --- | --- |
| New demo default | `cryosparcm downloadtest --dataset 10025` | `https://s3.wasabisys.com/cryosparc-test-data-dist/empiar_10025_subset_v1.tar` |
| EMPIAR-10305 | `cryosparcm downloadtest --dataset 10305` | `https://s3.wasabisys.com/cryosparc-test-data-dist/empiar_10305.tar.gz` |
| Performance benchmark | `cryosparcm downloadtest --dataset PERFORMANCE_BENCHMARK_DATA` | `https://s3.wasabisys.com/cryosparc-performance-benchmark-data/performance_benchmark_data_v1.tar.gz` |

新版 demo 使用 `empiar_10025_subset_v1.tar`。性能 benchmark job 代码另有一个
区域 endpoint：
`https://s3.us-east-1.wasabisys.com/cryosparc-performance-benchmark-data/performance_benchmark_data_v1.tar.gz`；这不是 `downloadtest` 命令使用的 URL。

镜像内也提供基于 `aria2c` 的下载脚本，dataset 参数与
`cryosparcm downloadtest` 相同：

```bash
cryosparc-download-data --dataset 10025
cryosparc-download-data --dataset 10305
cryosparc-download-data --dataset PERFORMANCE_BENCHMARK_DATA --output-dir /ssd
```

## Slurm Cluster

The workstation registers the local Docker worker and the Slurm cluster as
separate scheduler targets. The fixed configuration files are:

```text
/opt/cryosparc/cryosparc_master/bin/cluster_info.json
/opt/cryosparc/cryosparc_master/bin/cluster_script.sh
```

每个 Slurm 作业脚本会从新节点可见的 `~/.cryosparc/license_id` 读取并导出
`CRYOSPARC_LICENSE_ID`，镜像和 cluster template 不保存真实 license。

首次初始化时会执行一次 `cryosparcm cluster connect` 注册 cluster lane；之后
`start`/`restart` 直接使用数据库中的配置。修改这两个模板后，需要手动重新执行
`cryosparcm cluster connect` 才会生效。

The image includes the default cluster login host, controlled by the Dockerfile
`ARG CRYOSPARC_CLUSTER_HOSTS`:

```text
12.12.4.3 login03 login03.szbl.hpc etcd_node
```

### CryoSPARC Runtime Environment

官方默认值为 `false`，该变量用于绕过 CryoSPARC 对安装目录所有者的安全检查；license
一致本身不等于可以绕过这个文件所有者检查。由于镜像中的 `/opt/cryosparc` 由 `root`
所有、服务由映射后的运行用户执行，`cryosparc-workstation env` 会显式设置：

```bash
export CRYOSPARC_FORCE_USER=true
```

普通非容器安装不应默认打开这个 override。

当前容器的 hostname 与 `CRYOSPARC_MASTER_HOSTNAME` 不同，因此 `env` 仍会设置
`CRYOSPARC_FORCE_HOSTNAME=true`；如果容器 hostname 与 master hostname 改为一致，
可以移除这个 override。

### Slurm Resource Binding

Slurm 的配置文件位于：

```text
/opt/gridview/slurm/etc/slurm.conf
/opt/gridview/slurm/etc/gres.conf
/opt/gridview/slurm/etc/cgroup.conf
```

当前集群的资源绑定配置已确认如下：

- `SelectType=select/cons_tres`、`SelectTypeParameters=CR_CORE_MEMORY`：按可消耗的 CPU、内存和 GRES 资源分配作业。
- `TaskPlugin=task/affinity,task/cgroup`、`ProctrackType=proctrack/cgroup`：作业进程使用 CPU affinity 和 cgroup 管理。
- `/opt/gridview/slurm/etc/cgroup.conf` 设置 `ConstrainDevices=yes`、`ConstrainCores=yes`、`ConstrainRAMSpace=yes`、`ConstrainSwapSpace=no`；因此分配到的 GPU 设备和 CPU/内存范围会受到 cgroup 限制。
- `/opt/gridview/slurm/etc/gres.conf` 将每个节点的 `/dev/nvidia0` 到 `/dev/nvidia7` 注册为 `NVIDIAGeForceRTX4090D`，每张 GPU 绑定对应的 CPU 核心集合。
- `NV_4090D` 分区包含 `gn01` 到 `gn08`，共 64 张 GPU；分区默认值为每 GPU 8 CPU 和 102400 MB 内存。

当前 cluster script 使用动态资源模板：

```bash
#SBATCH --gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}
#SBATCH --partition NV_4090D
```

其中 `{{ num_gpu }}` 由 CryoSPARC 根据作业资源需求渲染。
`--gres=gpu:{{ 1 if num_gpu < 1 else num_gpu }}` 保证该 cluster lane 至少申请一张 GPU；多 GPU 作业仍按 CryoSPARC 的 `{{ num_gpu }}` 请求数量提交。
Slurm 再通过 GRES 和 cgroup 自动完成设备绑定；不需要在脚本中手工指定 `/dev/nvidia*` 或 `CUDA_VISIBLE_DEVICES`。
当前 `NV_4090D` 分区的 `JobDefaults=DefCpuPerGPU=8,DefMemPerGPU=102400` 会根据 GPU 数量自动提供 CPU 和内存，因此模板不再显式设置 `--cpus-per-task` 或 `--mem`。

CryoSPARC 官方 v5 文档将任务标记为 `GPU` 或 `Multi-GPU`；`Multi-GPU` 任务可以使用一张或多张 GPU。
例如 GPU 版 `Extract from Micrographs` 明确支持通过 `Number of GPUs` 参数并行化。
因此模板保留 `{{ num_gpu }}`，普通任务至少请求一张，多 GPU 任务按 CryoSPARC 资源分配请求多张。
模板中的 license 检查使用 `[[ ... ]] || { ...; }`，不要把 Shell 行写成以 `if` 开头；当前 CryoSPARC 的 Jinja line statement 会吞掉这类行首 `if`。
参考：
`https://guide.cryosparc.com/application-guide/creating-and-running-jobs.md`、
`https://guide.cryosparc.com/processing-data/all-job-types-in-cryosparc/extraction/job-extract-from-micrographs.md`。
如果需要验证具体作业，可以在作业脚本中记录 `CUDA_VISIBLE_DEVICES`、`SLURM_JOB_GPUS` 和 `SLURM_GPUS_ON_NODE`，但不要覆盖 Slurm 已设置的 `CUDA_VISIBLE_DEVICES`。

已在 `2026-08-25` 提交一次最小 GPU 作业验证绑定：请求
`--gres=gpu:1 --cpus-per-task=1 --mem=1G`，Slurm 作业 `784210` 在 `gn05` 上以
`COMPLETED 0:0` 结束，作业环境为：

```text
CUDA_VISIBLE_DEVICES=0
SLURM_JOB_GPUS=6
SLURM_GPUS_ON_NODE=1
/usr/bin/nvidia-smi
0, NVIDIA GeForce RTX 4090 D
```

这里 `SLURM_JOB_GPUS=6` 是节点上的物理 GRES 编号，而 `CUDA_VISIBLE_DEVICES=0`
是作业进程看到的重映射编号；`nvidia-smi` 只看到分配的这一张 GPU，说明 GRES 和
cgroup 设备绑定正在生效。

随后又验证了不显式设置 CPU 和内存、只请求 GPU 的情况：

- 作业 `784223` 使用 `--gres=gpu:1`，在 `gn02` 完成；`CUDA_VISIBLE_DEVICES=0`、`SLURM_JOB_GPUS=2`、`SLURM_GPUS_ON_NODE=1`、`SLURM_CPUS_ON_NODE=8`，`nvidia-smi` 只看到一张 RTX 4090 D。
- 作业 `784224` 使用 `--gres=gpu:2`，在 `gn02` 完成；`CUDA_VISIBLE_DEVICES=0,1`、`SLURM_JOB_GPUS=2,3`、`SLURM_GPUS_ON_NODE=2`、`SLURM_CPUS_ON_NODE=16`，`nvidia-smi` 看到两张 RTX 4090 D。

这说明当前 Slurm 的 GPU 数量请求、GPU 可见性和按 GPU 分配 CPU 默认值均已生效。

## Speed Test

必须使用 `--noproxy '*'`，否则可能受到本机代理环境影响。

普通 HTML 请求：

```bash
curl --noproxy '*' -sS -o /dev/null \
  -w 'http=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s bytes=%{size_download} speed=%{speed_download}B/s\n' \
  'http://10.68.247.45:40008/'
```

验证 gzip 响应头：

```bash
curl --noproxy '*' --compressed -sS -D - -o /dev/null \
  -w 'ttfb=%{time_starttransfer}s total=%{time_total}s bytes=%{size_download}\n' \
  'http://10.68.247.45:40008/'
```

测量容器内部服务，排除外部网络路径：

```bash
ssh -p 40002 xshu@10.68.247.45 \
  'curl --noproxy "*" -sS -o /dev/null -w "http=%{http_code} ttfb=%{time_starttransfer}s total=%{time_total}s bytes=%{size_download}\n" http://127.0.0.1:61000/'
```

## Observed Results

- 容器内 `61000`：HTTP `200`，TTFB 约 `1.2ms`，总耗时约 `1.3ms`。
- 外部 `40008` 普通请求：HTTP `200`，TTFB 约 `24ms`，总耗时约 `26ms`，HTML 约 `1308` bytes。
- 外部 `40008` gzip 请求：HTTP `200`，`Content-Encoding: gzip`，响应约 `658` bytes，总耗时约 `17-21ms`。
- `cryosparc-logo-small@2x.png`、`cryosparc-logo-text@2x.png` 等 logo 文件均返回 HTTP `200`。
- live 容器 logo 和本地 `ex/cryosparc_master/app/custom-server/dist/client/` 中对应文件的 SHA-256 一致。
- 登录后 `/api/utility/license` 返回协议内容，响应约 `11.9KB`；未认证时返回 `401`。
- 协议接受请求 `PUT .../licenseAccepted` 返回 `200`。
- 服务状态正常：database、Redis、API、scheduler、command、app 和 app_api 均为 `RUNNING`。

## Conclusions

- Web 服务和网络路径没有明显性能问题；外部约 `20-30ms`，容器内部约 `1ms`。
- 默认登录必须发送 SHA-256 后的密码；直接发送 `SZBL2026` 会得到 `Incorrect password`。
- 协议内容接口和静态 logo 文件都正常，问题不是文件缺失或服务未启动。
- 日志中曾出现 logo 首次请求被浏览器取消：`GET /CryoSPARC-logo-small@2x.png - -`，随后重新请求返回 `200`。手动打开图片后刷新页面能够显示，说明浏览器缓存命中了该资源；现象更接近首次请求取消或浏览器缓存/渲染问题。
