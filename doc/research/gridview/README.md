# GridView 研究

## 研究范围

本报告区分三类对象：仓库中的 CryoSPARC 镜像定义、历史 `cuda-ssh` GridView 构建记录，以及 2026-09-02 已有作业 `787683` 的只读 runtime 参数。三者不能互相替代。

容器和调度器的通用语义引用 [官方来源登记](../../official-sources.md)，CryoSPARC 产品要求引用 [CryoSPARC 官方来源登记](../../official-sources.md#cryosparc-官方资料)。

## 镜像与启动证据

### 当前仓库镜像

`containers/cryosparc5/Dockerfile:127-156` 在 `master0` 中复制 CryoSPARC wrapper、设置 runtime ENV、创建 `/ssd`、暴露 `22` 和 `61000-61006`，并设置 ENTRYPOINT `/usr/local/bin/cryosparc-container`。

`containers/cryosparc5/entrypoint:5-35` 的默认行为是启动 sshd、调用 `/usr/local/bin/cryosparc`，然后以 sleep loop 保持容器可用。仅有 Dockerfile ENTRYPOINT 的 inspect 结果，不能证明某个 GridView 运行实例一定执行了这个入口。

### n5 本地镜像

gpu14 上 `localhost/cryosparc-hybrid:n5` 的只读 metadata 如下：

| 项目 | 值 |
| --- | --- |
| Image ID | `67114eb657f7e613e82543eb4c72867499c34cbaf13434f8d69fc304d132357a` |
| Digest | `sha256:5afb2cfee0639eeb11e772503e2185feaa70fa700aebc6f4d2a1bd821e02b884` |
| Platform | `linux/amd64` |
| Size | 约 `14.97 GB` |
| Created | `2026-09-01T01:11:58Z` |
| Entrypoint | `/usr/local/bin/cryosparc-container` |
| Cmd/Volumes | `null` / `null` |

n5 内的 `/usr/local/bin/cryosparc-container` 在第 21 行调用 `/usr/local/bin/cryosparc-workstation`，而不是当前工作区 Dockerfile 复制的 `/usr/local/bin/cryosparc`。n5 history 也只有 `cryosparc-workstation` 的 COPY 记录。因此 n5 不能作为当前工作区 Dockerfile 产物的直接证明。

n5 探针使用 `--network none`、`--cap-drop=ALL`、`--security-opt=no-new-privileges`、`--read-only` 和临时 `/tmp`，只执行 `test`，输出为：

```text
test mode: no services, data, or license configuration will be changed
```

该探针证明的是 test 命令的非破坏性行为，不是默认入口的服务行为。

## GridView 镜像构建机制

历史 `cuda-ssh` import 记录给出了一个可以复核的 GridView 镜像加工链。它不是“把仓库 Dockerfile 直接 build 一次后运行”，而是先导入本地 archive，再叠加两轮平台 Dockerfile，最后推送到内部 registry：

```text
cuda-ssh.tar
  -> localhost/cuda-ssh:latest
  -> cuda-ssh01deea:cuda01deea
  -> cuda-ssh01deea:cuda01deea-sshd
  -> cuda-ssh:cuda
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
```

该 lineage 来自 `containers/cuda-ssh/deployment-check.md:494-519`：第一轮平台构建以内部 `cuda-ssh01deea:cuda01deea` 为 `FROM`，第二轮以 `cuda-ssh01deea:cuda01deea-sshd` 为 `FROM`，最终生成并推送 `cuda-ssh:cuda`。
最终 image ID 和 pull digest 与 import log 和 `760362_PULL.log` 对得上，因此这条 lineage 对该历史镜像成立；它不能证明当前 n5/h1 使用同一 provenance。

### 构建层与运行层的边界

历史 import 在镜像层中保留了 CUDA/Ubuntu 基础层、OpenSSH/sudo、`/run/sshd`、`PermitRootLogin`/`PasswordAuthentication`、`EXPOSE 22/61000` 和默认 `CMD ["/usr/sbin/sshd", "-D"]`。
GridView 额外加入了 root 用户、labels、`TZ=Asia/Shanghai`、`UseDNS no`、host key 生成、`/var/run/sshd` 和 `/root/.ssh` 等内容，具体证据见 `containers/cuda-ssh/deployment-check.md:521-557`。

下面这些不是镜像 build layer，而是 Slurm/实例启动时的参数或挂载：

- `--hostname worker-0`、`--entrypoint /bin/sh`、CPU/内存/GPU 限制和 `nvidia-docker run`。
- `/etc/hosts`、共享 home、`ai_sudoer`、SSH key、proxy、NVIDIA driver 和 Slurm framework mount。
- runtime setup 对 `sshd_config`、用户/密码和 `/etc/profile.d/sothisai.sh` 的写入。

这一区分解释了为什么 `podman image inspect` 只能看到 image 的默认 ENTRYPOINT/CMD，而不能还原 GridView 作业最终执行的命令。
Podman 官方文档也明确说明 build context、`--build-arg` 和 run 时的 `--entrypoint`、`--env`、`--mount`、`--device` 分属不同阶段，见[官方来源登记](../../official-sources.md#调度器和容器引擎官方资料)。

### 与 CryoSPARC 镜像的关系

当前 `containers/cryosparc5/Dockerfile` 的构建机制是仓库内可复现的多 stage build：先解包 master/可选 worker package，再在临时数据库中完成安装/patch，最后生成 `master`、`workstation` 和 `hybrid` target；最终镜像不携带预初始化业务数据库。
GridView 仍可在此基础上追加平台层，但追加层可能改变默认 CMD、入口脚本、ENV 和运行时挂载。

因此，判断一个 GridView 镜像是否能启动 CryoSPARC，必须同时核对镜像内 `/usr/local/bin/cryosparc-container`、其调用的 wrapper、平台的 `DC_ENTRYPOINT`/`DC_CMD_ARG` 和实际 mount；不能只看 tag、image history 或 Dockerfile 的 ENTRYPOINT。

历史构建还暴露出固定 root password 会进入 image history 的风险，见 `containers/cuda-ssh/deployment-check.md:573-575`。
本文不记录密码值；该历史 `cuda-ssh` 风险不能被当前 CryoSPARC license 处理方式自动消除。

### n5 event 查询

2026-09-02 在 gpu14 上对 n5 image 做了时间受限的只读查询：

```sh
podman events --since 2026-09-01T00:00:00Z \
  --until 2026-09-02T23:59:59Z \
  --filter type=image \
  --filter image=localhost/cryosparc-hybrid:n5
```

输出中能看到该 image ID 关联的 `pull` 和本地 tag 事件；没有在返回内容中看到 build 或 push provenance。
`podman events` 仍保持流式运行，命令在 30 秒后因超时终止，因此这次查询不能证明时间范围内不存在其他事件，也不能替代 registry audit 或 build log。
Q-001 仍为 `unresolved`。

### h1 与 commit 对照

已有 h1 容器内 `/usr/local/bin/cryosparc` 的 SHA-256 为 `3c15b19892dad8c4c8e000c77f767a2de3e630c559edf70a68bbb7acea30a2f0`，与当前工作区和 commit `8f8671509ca87860a889f5f0eaec266793aac4bc` 相同。h1 中观察到 supervisord、MongoDB、Redis、API、command、Web 等进程，但 PID 1 是 `/usr/sbin/sshd -D`。

这证明 h1 包含指定 commit 的 wrapper 并且运行时服务存在；它不能从 PID 或进程列表重建完整的原始 `docker run` 命令。

## GridView 外层启动链

对 login03 的只读脚本核验得到：

```text
Slurm Prolog
  -> /opt/gridview/slurm/etc/sothisai/slurm.prolog
  -> /opt/gridview/slurm/etc/sothisai/instance/job/prolog
  -> /opt/gridview/slurm/etc/sothisai/startRoleContainer.sh
  -> docker run / nvidia-docker run
```

关键证据位于 `doc/gridview-progress.md:89-117`：`slurm.conf` 的 `Prolog` 指向 `slurm.prolog`，instance prolog 调用 `startRoleContainer.sh`，后者在 `DC_ENTRYPOINT` 为空时设置 `/bin/sh`，GPU 路径调用 `nvidia-docker run`，最后由 runtime command 执行 sshd。

`/usr/bin/ai_docker` 只是管理/查看包装器，不是当前容器创建路径。历史 `cuda-ssh` 记录也显示最终运行命令使用 `--entrypoint /bin/sh` 和 `/usr/sbin/sshd -D`，见 `containers/cuda-ssh/deployment-check.md:267-343`。

## 已有作业 `787683`

宿主侧记录位于 `/lenovofs1/home/xshu/SothisAI/instance/ssh/hh1_1_0/`，已在 `doc/gridview-progress.md:200-276` 做了脱敏引用。

- `scontrol show job -dd 787683` 显示作业在 `gn02`、`NV_4090D` 分区运行，资源为 8 CPU、100G 内存和 1 GPU。
- `_dockerlist_787683` 记录容器 `787683_gn02`、别名 `worker-0`、IP `173.0.74.4`，没有 host port publish。
- `787683_gn02:27` 记录 `DC_ENTRYPOINT=" --entrypoint /bin/sh "`，`:29` 的 `DC_CMD_ARG` 以 runtime setup 开头并以 `/usr/sbin/sshd` 结束。
- `prolog.env.787683.gn02:137-146` 记录 `NV_GPU=0 timeout 90m nvidia-docker run`、`--hostname=worker-0`、shared hosts、NVIDIA/Slurm mounts、`--entrypoint /bin/sh` 和 h1 镜像。
- 最终 command 没有调用 `/usr/local/bin/cryosparc-container`、`/usr/local/bin/cryosparc-workstation` 或 `/usr/local/bin/cryosparc`。

因此已完成“还原该已有作业的 GridView 创建参数”的工作，但不能据此说 CryoSPARC 服务由该 `docker run` 启动。`787683.out:21` 还记录了 `sudo: unable to resolve host worker-0: Temporary failure in name resolution`；shared hosts 文件本身存在 `173.0.74.4 worker-0`，但该记录不足以确定具体解析时机或 namespace 原因。

## 历史镜像 lineage

历史 `cuda-ssh` 作业 `760362` 的可复核 lineage 为：

```text
/lenovofs1/home/xshu/cuda-ssh.tar
  -> localhost/cuda-ssh:latest
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea-sshd
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea-sshd-sudo
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
```

该 lineage 来自 `containers/cuda-ssh/deployment-check.md:494-519`，可证明历史 import log 和最终 digest 的对应关系；它不证明 n5 或 h1 使用同一 push 流程。

## URL prefix 结论

`/ai-forward/<id>/` 这类前缀与 CryoSPARC 页面输出的 root-absolute `/assets/*`、`/api/*` 和 WebSocket 路径不兼容。`containers/cryosparc5/live-test.md:175-218` 记录了容器内与外部请求的对比，以及资源和协议接口正常的结果。

结论是：无 prefix 的 socket 或独立端口转发是当前已验证的路径；不能把 nginx gzip、资源缺失或 CryoSPARC 服务未启动作为该 prefix 问题的直接解释。

## 未决范围

- n5 的原始 build/push provenance 不在 image inspect/history 中。
- h1 服务进程存在，但当前没有可审计的进程启动记录证明它由该次 GridView `docker run` 启动。
- 未对新的 GridView job 做 pull、start、Slurm submit 或服务 init；所有结论基于已有对象的只读记录。
- GridView platform behavior 依赖平台版本、分区和 runtime 注入；历史 `760362` 不能无条件推广到所有作业。
