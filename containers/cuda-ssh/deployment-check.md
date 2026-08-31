# cuda-ssh 部署检测记录

检测时间：2026-08-05

## 1. 检测入口

使用：

```text
/Volumes/Develop/git/szbl-hpc/Qbics/new/ssh/config
Host docker
HostName 10.68.247.45
Port 40009
User xshu
```

SSH 连接成功，容器 hostname 为 `worker-0`。

正式 `known_hosts` 中没有 `[10.68.247.45]:40009`，本次使用临时 known-hosts 文件接受当前 ED25519 host key，没有修改正式 SSH 配置。

## 2. 容器基本状态

| 项目 | 检测结果 |
| --- | --- |
| OS | Ubuntu 24.04.4 LTS |
| 登录用户 | `xshu`，UID `5060`，GID `hpc_core` |
| root 切换 | `sudo -n su -c id` 成功，得到 UID `0` |
| PID 1 | `/usr/sbin/sshd -D` |
| 容器内监听 | `0.0.0.0:22`，以及临时 HTTPS 测试服务 `0.0.0.0:61000` |
| 容器 IP | `173.0.51.2` |
| `/bin/sh` | 链接到 `/bin/bash` |

初始连接时容器只启动了 SSH daemon，没有启动 CryoSPARC、HTTP/HTTPS 服务或 60000 端口服务。后续为验证端口链路，在容器内临时启动了 TLS 服务监听 61000；该服务不属于镜像默认启动项，容器重启后不会自动恢复。

每次 SSH 命令都会出现以下环境告警：

```text
setlocale: LC_ALL: cannot change locale (en_US.UTF-8): No such file or directory
error: could not lock config file /lenovofs1/home/xshu/.gitconfig: File exists
```

前者是 locale 未安装或未生成；后者来自共享 home 下的 `.gitconfig` 操作，可能是平台注入的 shell 初始化逻辑并发触发。

## 3. 挂载情况

容器根目录是 Docker overlay，另外注入了共享文件系统、平台目录和 NVIDIA runtime 文件。

| 容器路径 | 来源/类型 | 访问情况 |
| --- | --- | --- |
| `/` | Docker `overlay` | `rw`，406G，总使用 39G，可用 347G |
| `/lenovofs1/home/xshu` | `lenovofs1` GPFS，来源 `/home/xshu` | `rw`，约 3.2P，总使用 294T，可用 2.9P |
| `/opt/ib_driver` | `lenovofs1` GPFS，来源 `/SothisAI/ib_driver` | `rw` |
| `/opt/SothisAI` | `/dev/sda4` ext4，来源 `/opt/gridview/scripts/scheduler/slurm/instance` | `rw` |
| `/etc/motd` | `lenovofs1` 实例文件 | 平台注入 |
| `/etc/hosts` | `lenovofs1` shared hosts 文件 | 平台注入 |
| `/etc/sudoers.d/ai_sudoer` | `lenovofs1`，来源 `/home/xshu/.ai_user_info/ai_sudoer` | root-owned，644 |
| `/usr/share/zoneinfo/Etc/UTC` | `/dev/sda4` ext4 | `ro` |

NVIDIA 相关挂载：

- `/dev/nvidiactl`
- `/dev/nvidia-uvm`
- `/dev/nvidia-uvm-tools`
- `/dev/nvidia4`
- `/dev/nvidia5`
- `/proc/driver/nvidia`
- `/run/nvidia-persistenced/socket`
- NVIDIA 用户态库和工具，版本 `570.133.07`

这说明 GPU、driver 和共享 home 不是由本地 `Dockerfile` 单独提供，而是由部署平台在创建容器时注入。

## 4. GPU 检测

容器内 `nvidia-smi` 成功：

```text
0, NVIDIA GeForce RTX 4090 D, 570.133.07, 24564 MiB
1, NVIDIA GeForce RTX 4090 D, 570.133.07, 24564 MiB
```

实际可见 2 张 RTX 4090 D，每张约 24 GiB 显存。

## 5. 参考 Dockerfile 与部署后的变化

### 5.1 本地 Dockerfile

`containers/cuda-ssh/Dockerfile` 的主要内容：

- 基础镜像：`nvidia/cuda:12.8.2-base-ubuntu24.04`
- 安装 `openssh-server`、`openssh-client`、`sudo`、`passwd`、`vim`、证书和 bash completion
- 修改 sshd，允许 root 登录和密码认证
- 创建 `/run/sshd`
- `EXPOSE 22` 和 `EXPOSE 61000`
- `CMD ["/usr/sbin/sshd", "-D"]`

### 5.2 GridView 部署日志

`gridview.import.log` 显示实际部署不是直接使用本地 Dockerfile，而是经过两层生成镜像：

1. 从 registry 基础镜像 `cuda-ssh01deea:cuda01deea` 构建 sshd 层。
2. `USER root`，设置 `DEBIAN_FRONTEND` 和 `TZ=Asia/Shanghai`。
3. 将 source/resource 复制到临时目录。
4. 因 `VALID_VERSION=false`，没有替换 `/etc/apt` 的离线源内容；日志同时提示 Ubuntu 24.04 版本不在平台支持列表中。
5. 创建 `/var/run/sshd` 和 `/root/.ssh`。
6. 设置 `UseDNS no`。
7. 注释 sshd 的 `pam_nologin.so` 检查。
8. 执行 `ssh-keygen -A`，暴露端口 22。
9. 第二层确保 `sudo` 存在，并执行 `/bin/sh -> /bin/bash`。
10. 最终镜像被标记并推送为平台的 `cuda-ssh` 镜像。

实际运行容器的 PID 1 为 `sshd -D`，与上述部署结果一致。

### 5.3 运行时安装的诊断软件

按要求在运行中容器内通过 apt 安装了：

```text
iproute2
curl
netcat-openbsd
jq
```

这些安装只改变当前容器的 writable layer，没有回写本地 `Dockerfile`。如果需要可复现，应把它们加入镜像构建阶段。

## 6. 本机端口映射测试

### 6.1 SSH

```text
本机: 10.68.247.45:40009
容器: 22
结果: SSH 登录成功
```

### 6.2 socket

测试命令：

```bash
nc -vz -w 5 10.68.247.45 40003
```

结果：

```text
Connection to 10.68.247.45 port 40003 [tcp/*] succeeded!
```

但是容器内测试：

```bash
nc -vz -w 5 127.0.0.1 60000
```

结果为 `Connection refused`，并且 `ss -lntup` 没有 60000 listener。

结论：

- `10.68.247.45:40003` 当前 TCP 入口可达。
- 不能证明它已经映射到当前容器的 `60000` 服务。
- 当前容器内没有启动 60000 服务；可能是平台侧端口、其他容器或外部服务在响应。

### 6.3 HTTP

测试 URL：

```text
http://10.68.247.45:6080/ai-forward/2084851767723941889610000010/
```

结果：

```text
HTTP/1.1 404 Not Found
Server: nginx/1.30.1
```

说明本机可以访问 `10.68.247.45:6080` 的 nginx，但给定的 `ai-forward` 路由不存在，或没有部署到当前服务。启动容器内 TLS 服务后再次测试，HTTP 请求仍返回 `404`，说明该入口没有建立可验证的 HTTPS 转发链路。

容器内的 61000 当前按 HTTPS 监听，因此不再使用明文 HTTP 请求测试该端口。

### 6.4 HTTPS

为验证容器内必须使用 HTTPS 的场景，在运行中的容器内生成了临时自签名证书，并启动 TLS server：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -keyout /tmp/cuda-ssh.key -out /tmp/cuda-ssh.crt \
  -subj /CN=worker-0 -addext subjectAltName=IP:173.0.51.2
```

当前监听状态：

```text
LISTEN 0 5 0.0.0.0:61000 0.0.0.0:* users:(("python3",pid=1162,fd=3))
LISTEN 0 128 0.0.0.0:22    0.0.0.0:*
```

测试结果：

| 路径 | 命令 | 结果 |
| --- | --- | --- |
| 容器本机 | `curl -k https://127.0.0.1:61000/` | `200` |
| `ln03` 直连容器 | `curl -k --noproxy '*' https://173.0.51.2:61000/` | `200` |
| 本机 HTTPS 中转 | `https://10.68.247.45:6080/ai-forward/...` | TLS 握手失败 |
| `ln03` HTTPS 中转 | 同上 | `wrong version number` |

`-k` 仅用于忽略临时自签名证书校验。直连结果证明容器内 HTTPS listener 和 `ln03` 到容器的网络路径正常；6080 入口目前仍按 HTTP 提供服务，不是可用的 HTTPS 入口。

## 7. 当前部署结论

| 功能 | 结果 | 说明 |
| --- | --- | --- |
| SSH 登录 | 通过 | `40009 -> 22` 正常 |
| passwordless sudo | 通过 | `sudo -n su` 可切 root |
| GPU | 通过 | 2 张 RTX 4090 D，driver 570.133.07 |
| home 共享挂载 | 通过 | `/lenovofs1/home/xshu` 为 GPFS |
| CUDA driver 注入 | 通过 | 设备、库、`nvidia-smi` 均可见 |
| socket 40003 | TCP 可达 | 当前容器 60000 未监听 |
| HTTP 6080 | nginx 可达 | 指定路径返回 404 |
| 容器 61000 HTTPS | 通过 | 容器本机和 `ln03` 直连均返回 `200` |
| HTTPS 中转 6080 | 未通过 | 6080 当前不是可用的 HTTPS 入口 |

## 8. 对 CryoSPARC 部署的影响

当前 `cuda-ssh` 镜像只适合作为带 SSH/GPU 的基础 worker 容器，还没有运行 CryoSPARC 服务。

如果要把它作为 workstation/master 容器，需要额外完成：

1. 在容器内安装并配置 CryoSPARC master/worker。
2. 启动 master 服务，使其绑定 `0.0.0.0:61000` 或实际配置的 base port。
3. 如果需要 socket 服务，启动服务并确认绑定 `0.0.0.0:60000`。
4. 将平台映射明确配置为 `40003 -> 60000`、`6080 -> 61000`，并确认 6080 使用 HTTPS；如果由 nginx 终止 TLS，还要确认 upstream 协议为 HTTPS。
5. 重新测试容器内部 HTTPS listener、本机映射端口和 HTTPS 路由。
6. 将 apt 诊断依赖和 locale 修复写入最终 Dockerfile，而不是依赖运行时手工安装。

## 9. Slurm 容器启动链路

### 9.1 作业定位

在 `ln03` 上通过 Slurm 查询到当前运行作业：

| 项目 | 值 |
| --- | --- |
| JobId | `760362` |
| JobName | `Instances_2608051157325958_0_0` |
| NodeList / BatchHost | `gn07` |
| 资源 | 16 CPU、200G 内存、2 张 GPU |
| Command | `/lenovofs1/home/xshu/SothisAI/instance/ssh/Instances_2608051157325958_0_0/job_xshu_20260805_115931` |
| 作业日志 | `/lenovofs1/home/xshu/SothisAI/instance/ssh/Instances_2608051157325958_0_0/760362.out` |
| 容器参数记录 | `/lenovofs1/home/xshu/SothisAI/instance/ssh/Instances_2608051157325958_0_0/760362_gn07` |

`760362.out` 记录了：

```text
docker pull image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
760362_gn07 启动完成
```

`760362_PULL.log` 记录镜像 digest：

```text
sha256:ab565c6b2cb27a0a0613ae766b641f34a6c9159d16d55ebd33791d14cbe7d235
```

### 9.2 启动脚本关系

当前已经确认的调用链为：

1. Slurm 作业脚本 `job_xshu_20260805_115931` 由 `scontrol show job 760362` 的 `Command` 字段确认。
2. 作业脚本加载 `/opt/gridview/slurm/etc/sothisai/function.sh`，并启动容器相关的框架逻辑。
3. `/opt/gridview/slurm/etc/sothisai/instance/job/prolog` 定义 `startRoleContainer`，为 instance 作业调用 `startRoleContainer.sh`。
4. `startRoleContainer` 最终执行：

```bash
sh /opt/gridview/slurm/etc/sothisai/startRoleContainer.sh \
  "$TASK_PATH" "$DC_NAME" "$SLURM_JOB_ID"
```

5. `/opt/gridview/slurm/etc/sothisai/startRoleContainer.sh` 组装 `docker_run_cmd`，最后通过 `eval` 执行。

`/usr/bin/ai_docker` 只是 `/opt/gridview/scripts/scheduler/ai_docker/ai_docker` 的包装入口；其 `ai_docker_util` 中的运行函数最终调用 Docker。当前容器创建命令的具体组装位置是 `startRoleContainer.sh`，不是 `ai_docker` 包装脚本本身。

### 9.3 本次作业的 Docker 参数

`760362_gn07` 是本次作业生成的参数记录文件，包含以下关键值：

```text
DC_NAME=760362_gn07
DC_GPUIDS=4,5
ALIAS=worker-0
DC_CONTAINER_PORT=8888
DC_PORTS_MAP=""
DC_IMAGENAME=image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
```

GPU 作业使用的运行命令模板来自 `startRoleContainer.sh`：

```bash
NV_GPU=4,5 timeout 90m nvidia-docker run \
  -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
  --cpuset-cpus=32,33,34,35,36,37,38,39,48,49,50,51,52,53,54,55 \
  --memory=204800M --shm-size=204800M \
  --name 760362_gn07 -d \
  --hostname worker-0 \
  -v /lenovofs1/home/xshu/SothisAI/instance_service/Instances_2608051157325958/shared_hosts:/etc/hosts \
  ...framework mounts and environment... \
  --entrypoint /bin/sh \
  image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda \
  -c '...runtime setup...; /usr/sbin/sshd -D'
```

实际挂载包括：

- `/lenovofs1/home/xshu:/lenovofs1/home/xshu`
- `/lenovofs1/SothisAI:/lenovofs1/SothisAI:ro`
- `/opt/gridview/scripts/scheduler/slurm/instance/:/opt/SothisAI/`
- `/lenovofs1/SothisAI/ib_driver/:/opt/ib_driver/:ro`
- 作业专属 `motd` 文件到 `/etc/motd`
- 作业专属 `shared_hosts` 文件到 `/etc/hosts`
- `.ai_user_info/ai_sudoer` 到 `/etc/sudoers.d/ai_sudoer`

本次 `DC_PORTS_MAP` 为空，说明 Docker 本身没有配置 host port publish；容器通过 Docker 网络 IP `173.0.51.2` 提供访问。

### 9.4 容器内 sshd 的启动方法

Slurm 的 instance prolog 在构造 `DC_CMD_ARG` 时会：

- 更新容器内 `/etc/passwd`、`/etc/group` 和 `/etc/shadow`。
- 根据 `/proc/1/environ` 生成 `/etc/profile.d/sothisai.sh`。
- 写入 `/etc/ssh/sshd_config`，包括 `ListenAddress 0.0.0.0`、`Port 22`、密码认证和公钥认证配置。
- 清理并复制 `/root/.ssh`。
- 写入 sudo 和代理相关配置。
- 最后执行 `/usr/sbin/sshd -D`。

因此，`760362_gn07` 确实是这次启动参数和命令片段的关键记录，但它本身不是独立的启动脚本；真正的启动逻辑在 `instance/job/prolog` 和 `startRoleContainer.sh`。容器内 PID 1 已验证为：

```text
sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
```

`760362_gn07` 原始 `DC_CMD_ARG` 中包含运行时生成的用户密码字段，本文不复制该敏感值。

## 10. 容器内 Podman 和 GPFS 存储

### 10.1 Podman 安装

已在运行中的 `cuda-ssh` 容器内安装 Podman：

```text
podman version 4.9.3
```

安装同时带入 `buildah`、`crun`、`fuse-overlayfs`、`netavark` 等依赖。该安装只改变当前容器 writable layer，没有修改本地 Dockerfile。

### 10.2 GPFS 与 Podman 存储

文件系统检测结果：

| 路径 | 文件系统 | 结论 |
| --- | --- | --- |
| `/` | Docker `overlay` | 本地容器根盘，可用于临时测试 |
| `/tmp` | Docker `overlay` | 本地盘，可用于 Podman 临时存储 |
| `/lenovofs1/home/xshu` | `gpfs` | 不建议放 rootless overlay 存储 |

容器内没有 `xshu` 的 `/etc/subuid` 和 `/etc/subgid` 范围。Podman rootless 会退化为单 UID/GID 映射，并提示该模式可能影响镜像文件所有权。

已验证可用的安全测试配置为：

```bash
podman \
  --root /tmp/podman-xshu-root \
  --runroot /tmp/podman-xshu-run \
  --storage-driver=vfs \
  info
```

这避免了两类问题：rootless 默认 graphroot 落到 GPFS，以及在 GPFS 上使用 overlayfs。

### 10.3 Harbor 解析和拉取状态

`ln03` 上解析到：

```text
12.12.4.9 image.ac.com
```

`ln03` 访问 `https://image.ac.com:5000/v2/` 返回 Harbor 的 `401 Unauthorized`，说明网络和 registry 服务正常。容器原始 `/etc/hosts` 是平台挂载的 GPFS 文件，只包含 `worker-0`，没有 `image.ac.com` 条目，因此容器内直接解析失败。

当前容器的 `/etc/hosts` 已补充：

```text
12.12.4.9 image.ac.com
```

该文件实际是 GPFS 上的作业共享 hosts 文件：

```text
/lenovofs1/home/xshu/SothisAI/instance_service/Instances_2608051157325958/shared_hosts
```

因此该修改属于当前 instance 的共享 hosts 配置，不是 Dockerfile 修改。

### 10.4 Podman 拉取结果

rootless Podman 已经能够连接 Harbor 并下载 layer，但在解包阶段失败：

```text
potentially insufficient UIDs GIDs available in user namespace
lchown /etc/gshadow: invalid argument
```

原因是容器内没有 `xshu` 的 subuid/subgid 范围。随后使用 rootful Podman，并继续使用本地 `vfs` 存储成功拉取：

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  -u all_proxy -u ALL_PROXY NO_PROXY='*' no_proxy='*' \
sudo podman \
  --root /tmp/podman-rootful-root \
  --runroot /tmp/podman-rootful-run \
  --storage-driver=vfs \
  pull --tls-verify=false \
  image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
```

结果：

```text
image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
digest: sha256:ab565c6b2cb27a0a0613ae766b641f34a6c9159d16d55ebd33791d14cbe7d235
size: 180 MB
storage driver: vfs
```

Podman inspect 得到的镜像默认配置为：

```text
Entrypoint: null
Cmd: ["/usr/sbin/sshd", "-D"]
ExposedPorts: 22/tcp, 61000/tcp
```

结论：容器内可以拉取该 Harbor 镜像，但建议使用 rootful Podman 或先为 `xshu` 配置 subuid/subgid；存储应放在本地 overlay 根盘下的目录，并使用 `vfs`，不要把 Podman overlay graphroot 放到 GPFS。`--tls-verify=false` 只用于本次验证，正式使用应把 Harbor CA 正确配置到 Podman 的 cert directory。

## 12. Harbor 其他镜像 Pull/Push 测试

### 12.1 Pull

import log 中的中间 tag：

```text
image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea
```

并没有作为可拉取的独立 repository 推送到 Harbor，Podman 返回：

```text
repository gpu/xshu/base/cuda-ssh01deea not found
```

通过 Harbor token 查询到当前 `base/` 下另一个实际存在的镜像：

```text
image.ac.com:5000/gpu/xshu/base/vscode-pytorch-plus:galaxy
```

其 manifest 有 37 个 layer，压缩大小约 8.8GB。使用容器内 rootful Podman、`vfs` 存储和无代理环境执行 pull 后，已经开始收到并下载 layer，证明：

- 容器到 Harbor 的网络路径正常。
- `gpu/xshu/base/` 下其他 repository 的 pull 权限正常。
- 不需要完整下载 8.8GB 镜像即可确认 pull 端点和权限可用。

完整 pull 按要求中止，临时 layer 已清理，没有保留该 8.8GB 镜像。

### 12.2 Push

未修改镜像内容，只把现有镜像改成唯一测试 tag：

```text
image.ac.com:5000/gpu/xshu/base/cuda-ssh-push-probe:probe-20260805-1550
```

执行 push 时请求确实到达 Harbor，但在创建 blob upload 阶段返回：

```text
unauthorized access repository: gpu/xshu/base/cuda-ssh-push-probe, action: push
```

随后查询该 repository 返回 `404 repository not found`，说明测试没有创建远端 repository/tag。本地 probe tag 也已清理。

结论：当前容器使用的 Podman 没有 push 权限或有效的 Harbor push 凭据；pull 权限和 push 权限是分开的。问题不是网络、DNS 或 TLS，push 请求已经到达 registry，失败点是 Harbor 认证/授权。

## 11. 拉取镜像与 Dockerfile 的关系

### 11.1 镜像血缘

`image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda` 不是只按仓库中的 `containers/cuda-ssh/Dockerfile` 直接构建出的 tag。根据 `gridview.import.log`，可确认的加工链为：

```text
/lenovofs1/home/xshu/cuda-ssh.tar
  -> localhost/cuda-ssh:latest
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea-sshd
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh01deea:cuda01deea-sshd-sudo
  -> image.ac.com:5000/gpu/xshu/base/cuda-ssh:cuda
```

证据：

- import log 第 2-3 行显示先加载 `cuda-ssh.tar`，源 tag 是 `localhost/cuda-ssh:latest`。
- 第 11 行显示第一轮 GridView Dockerfile 的 `FROM` 是内部中间镜像 `cuda-ssh01deea:cuda01deea`。
- 第 85-86 行生成 `cuda01deea-sshd`。
- 第 92 行以 `cuda01deea-sshd` 为第二轮构建的 `FROM`。
- 第 282-286 行生成最终镜像，并推送为 `cuda-ssh:cuda`。
- Podman 拉到的镜像 ID 是 `98a491d4e860...`，与 import log 第 282 行的最终 build ID `98a491d4e860` 一致。
- Podman inspect 得到的 RepoDigest 与 `760362_PULL.log` 中的 digest 一致。

因此，当前拉取的镜像就是该 import log 生成的最终镜像；仓库 Dockerfile 是其底层来源之一，GridView 又在其上增加了两轮构建层。

### 11.2 Dockerfile 保留下来的配置

仓库 `Dockerfile` 的以下内容在最终镜像 history 中仍然存在：

| Dockerfile 配置 | 最终镜像状态 |
| --- | --- |
| `FROM nvidia/cuda:12.8.2-base-ubuntu24.04` | CUDA 12.8.2、Ubuntu 24.04 基础层仍在 history 中 |
| 安装 OpenSSH、sudo、passwd、vim、证书和 bash completion | 对应的约 85.5MB apt 层仍在 history 中 |
| 创建 `/run/sshd` | 保留；GridView 又执行了 `/var/run/sshd` 创建 |
| `PermitRootLogin yes`、`PasswordAuthentication yes` | 初始配置保留，运行时还会再次覆盖 sshd 配置 |
| `EXPOSE 22`、`EXPOSE 61000` | 最终 inspect 仍显示两个端口 |
| `CMD ["/usr/sbin/sshd", "-D"]` | import 二次构建没有覆盖 CMD，最终 inspect 仍为该值 |

`EXPOSE 61000` 和 `CMD` 并不是 import log 第二轮新增的；它们是从内部中间镜像继承下来的。import log 中明确新增的只有 `EXPOSE 22`。

### 11.3 GridView import 新增或改变的内容

import log 显示 GridView 构建过程新增了这些内容：

| 配置 | 变化 |
| --- | --- |
| 基础引用 | 最终构建不直接引用 `nvidia/cuda`，而是引用内部 `cuda-ssh01deea` 中间镜像 |
| `USER root` | 两轮构建都显式设置为 root；最终镜像默认用户为 root |
| Labels | 增加 `author=sugon`、`email=sugon@sugon.com`、`author=slurm `、`email=slurm@sugon.com` |
| Environment | 增加 `TZ=Asia/Shanghai`；`DEBIAN_FRONTEND=noninteractive` 被保留 |
| 构建参数 | 加入 `VALID_VERSION=false`、空的 `VERSION`、临时 source/resource 目录参数 |
| apt source | 因 Ubuntu 24.04 被标记为不支持，`VALID_VERSION=false`，没有用导入的 source 覆盖 `/etc/apt` |
| SSH 检查 | 检查 `sshd -p 22`，必要时才安装 openssh-server；本次基础镜像已有 SSH，因此应主要走检查路径 |
| SSH 目录 | 创建 `/var/run/sshd` 和 `/root/.ssh` |
| `UseDNS` | 修改为 `UseDNS no` |
| PAM | 注释 `/etc/pam.d/sshd` 中的 `pam_nologin.so` 检查 |
| Host keys | 执行 `ssh-keygen -A`；失败时才尝试离线 RSA key 生成 |
| shell | 第二轮执行 `ln -fs /bin/bash /bin/sh` |
| sudo | 第二轮检查 `sudo -V`；已经存在时不重新安装；最终记录为 sudo 1.9.15p5 |
| 临时文件 | `source`、`resource` 被 COPY 到临时目录后，在每一轮末尾删除 |

最终镜像 inspect 还显示了 GridView/NVIDIA 侧的 labels 和环境变量，例如 `NVIDIA_VISIBLE_DEVICES=all`、`NVIDIA_DRIVER_CAPABILITIES=compute,utility`、`CUDA_VERSION=12.8.2`，这些不是仓库 Dockerfile 中显式写出的配置。

### 11.4 不属于镜像构建层的运行时变化

下面这些内容来自 Slurm 启动命令和挂载，不在最终镜像本身：

- `--hostname worker-0`。
- `--entrypoint /bin/sh`。
- GPU、CPU、内存、共享内存和 `nvidia-docker run` 参数。
- `/etc/hosts`、home、`ai_sudoer`、用户 passwd/group/shadow、SSH key 和 proxy 文件挂载。
- Slurm 在 `DC_CMD_ARG` 中重写 `/etc/ssh/sshd_config`，然后执行 `/usr/sbin/sshd -D`。
- Slurm 运行时写入 sudo 配置、用户密码和 `/etc/profile.d/sothisai.sh`。
- 本次手工安装的 Podman、curl、jq、netcat 和 iproute2。

所以，镜像 inspect 看到的默认 CMD 是 `/usr/sbin/sshd -D`，而运行中的容器仍由 Slurm 的 `/bin/sh -c` 初始化命令接管；这解释了为什么运行时的 sshd 配置比 Dockerfile 和镜像本身更完整。

### 11.5 安全问题

仓库 Dockerfile 使用 build arg 设置 root 密码。该密码虽然不出现在最终 config 的普通环境变量中，但会出现在 image history 的 `RUN chpasswd` 创建命令中，并随镜像发布。这个密码应立即轮换，后续应改为运行时注入 secret，不要在 Dockerfile 或 build arg 中写入固定密码。

## 12. Workstation 镜像构建与启动测试

### 12.1 构建文件

新增文件：

```text
containers/cryosparc5/Dockerfile
containers/cryosparc5/cryosparc
```

Dockerfile 的主要阶段如下：

1. `runtime-base`：准备 CUDA 12.8.2、OpenSSH、运行库和诊断工具。
2. `installer-base` 及可选 package stages：始终直接解包 master 包；`CRYOSPARC_INCLUDE_WORKER` 默认开启，通过 `installer-worker-true/false` 按需解包 worker 包。
3. `installer`：只复制 `pkg/` 根目录下的 patch 包，使用 `--exclude='pkg/*/**'` 排除备份旧版等子目录，并运行存在的 master/worker 安装器；如果本地存在 patch 包则在构建期间安装，否则跳过。构建期间临时使用数据库完成安装和 patch。
4. `master0`、`master`、`workstation`、`hybrid`：从安装阶段复制对应最终安装目录，不携带预初始化数据库或用户。

构建默认使用 `CRYOSPARC_WORKER_NOGPU=true`，因此构建机器不需要 GPU。构建阶段使用格式合法的占位 license；真实 license 不写入镜像，在首次运行时由 `cryosparc` 输入。

### 12.2 gpu14 构建结果

在 `gpu14` 上使用本地镜像：

```text
docker.io/nvidia/cuda:12.8.2-base-ubuntu24.04
```

Podman 构建成功，最终测试镜像：

```text
localhost/cryosparc-workstation:test3
```

构建日志确认：

- master 和 worker 压缩包成功解压。
- master/worker 依赖成功安装。
- 构建阶段没有 GPU 检测失败。
- 自动 license-server patch 探测已跳过。
- master patch 和 worker patch 均从 `pkg/` 本地包安装。
- 构建期间 master 数据库和 patch 安装成功；最终镜像不包含该临时数据库。

### 12.3 cryosparc 启动测试

使用 rootless Podman 的 `--userns=keep-id` 运行测试。直接指定容器内 `1000:1000` 会因当前 rootless UID 映射不能写入 home 挂载；`--userns=keep-id` 可以正确保持用户 home 的 UID/GID。

测试结果：

| 检查项 | 结果 |
| --- | --- |
| 首次 license 配置 | 通过；本次 smoke test 用环境变量模拟输入，license 保存到 `~/.cryosparc/license_id`；TTY 交互由 `cryosparc` 通过默认入口提供 |
| license 文件权限 | `600`，由运行用户拥有 |
| 首次 init 数据库 | 通过；运行时在 `~/.cryosparc/cryosparc_database` 初始化 WiredTiger 数据 |
| scratch 目录 | 通过；worker target 默认使用 `/ssd`，可由 `CRYOSPARC_SCRATCH_PATH` 覆盖 |
| project 目录 | 通过；创建 `~/cryosparc_projects` |
| master 服务 | 通过；database、cache、api、scheduler、app 均启动 |
| worker 注册 | 通过；本机 worker 注册到 `localhost:61000`，SSD 预留默认 `768 MB`，可由 `CRYOSPARC_SSD_RESERVE` 覆盖 |
| Slurm cluster 注册 | 默认连接 `szbl-cluster`，与本机 Docker worker 同时作为独立 scheduler target 列出；可由 `CRYOSPARC_CLUSTER_ENABLED=false` 禁用 |
| cluster hosts | 镜像构建时添加 `12.12.4.3 login03 login03.szbl.hpc etcd_node` 到 `/etc/hosts` |
| 无 GPU 运行 | 通过；worker 使用 `--no-gpu`，不启用 GPU 资源 |
| base port | 通过；`61000` 返回 HTTP `200` |

`cryosparc` 的默认行为是 `init`、`start`、`status`；初始化用户和数据库保存在运行用户的 home 中。停止后再次启动时不再传入 license 环境变量，脚本从已保存的 `~/.cryosparc/license_id` 和数据库继续启动，master、worker 和 61000 均恢复正常。

本 workstation smoke test 验证的是 CryoSPARC 原生 base port 的 HTTP 服务。CryoSPARC 本身不会因为此 Dockerfile 自动变成 TLS；如果平台要求 61000 在容器内必须是 HTTPS，需要另外配置证书和 TLS 终止层，并将 CryoSPARC 原生 HTTP 端口改为内部端口。

### 12.4 与 GridView 启动链路的关系

当前 GridView/Slurm 启动参数会显式设置 `--entrypoint /bin/sh`，并在运行时执行 `/usr/sbin/sshd -D`。因此直接使用 workstation 镜像默认 `ENTRYPOINT` 时，`cryosparc-container` 会启动；但如果沿用现有 GridView 的 entrypoint 覆盖逻辑，必须把 `/usr/local/bin/cryosparc-container` 加入平台的 runtime setup，不能只依赖 Dockerfile 的 `ENTRYPOINT`。
