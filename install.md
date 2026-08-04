下面按 **Single Workstation（Master+Worker 合并）**、**Master-Worker 分离架构**、**HPC Cluster（Slurm 等调度器）** 三种方式整理 CryoSPARC 安装方式、参数含义和网络端口。内容基于官方安装文档。([CryoSPARC Guide][1])

---

# 1. CryoSPARC 架构概念

CryoSPARC 由两个主要组件组成：

```
                 Browser
                    |
                    |
              cryosparc_master
              (Web + DB + Scheduler)
                    |
          -----------------------
          |                     |
   cryosparc_worker        cryosparc_worker
      GPU node                GPU node
```

## Master

负责：

* Web UI
* 用户管理
* Project / Job metadata
* MongoDB database
* Job dispatch
* Worker heartbeat

通常：

* CPU
* 大内存
* 稳定磁盘

即可。

---

## Worker

负责：

* GPU 计算
* FFT
* Reconstruction
* Refinement
* Motion correction 等

要求：

* NVIDIA GPU
* NVIDIA Driver >= 520.61.05（新版本要求）([CryoSPARC Guide][1])

---

# 2. Single Workstation（单机模式）

适合：

* 实验室工作站
* 1~4 GPU
* 不需要共享集群

结构：

```
             Browser
                |
                |
        +----------------+
        | workstation    |
        |                |
        | cryosparc_master
        |        |
        | cryosparc_worker
        |        |
        |      GPU
        +----------------+
```

Master 和 Worker 在同一台机器。

官方称：

> Both the CryoSPARC master and worker processes may run on the same machine. ([CryoSPARC Guide][2])

---

## 2.1 安装目录

例如：

```
/opt/cryosparc
```

安装后：

```
/opt/cryosparc/
 ├── cryosparc_master
 └── cryosparc_worker
```

注意：

安装目录不能随便移动。

官方要求安装路径（解析软链接后）不要超过 83 字符。([CryoSPARC Guide][1])

---

# 3. Single Workstation 安装命令

示例：

```bash
./install.sh \
  --license $LICENSE_ID \
  --standalone \
  --ssdpath /scratch/cryosparc_cache \
  --port 61000
```

---

## 参数解释

| 参数             | 含义                   |
| -------------- | -------------------- |
| `--license`    | CryoSPARC license ID |
| `--standalone` | 单机 master+worker     |
| `--ssdpath`    | worker 本地 SSD cache  |
| `--nossd`      | 不使用 SSD              |
| `--port`       | CryoSPARC base port  |

---

## 用户初始化参数

安装时：

```
--initial_email
--initial_username
--initial_firstname
--initial_lastname
--initial_password
```

用于创建第一个管理员账号。([CryoSPARC Guide][1])

---

# 4. Master-Worker 分离模式

适合：

* 多 GPU server
* 实验室服务器
* 小型 HPC

架构：

```
                 Browser
                    |
                    |
             cryosparc_master
             hostname master01
                    |
          -------------------
          |                 |
       worker01          worker02
       GPU node          GPU node

```

官方要求：

1. 所有节点共享 filesystem
2. Master 可以 passwordless SSH 到 worker
3. Worker 能访问 Master 的 10 个 TCP port ([CryoSPARC Guide][2])

---

# 5. Master 安装

例如：

```
master01
```

安装：

```bash
./install.sh \
 --license $LICENSE_ID \
 --hostname master01 \
 --port 61000 \
 --dbpath /data/cryosparc_database
```

---

参数：

| 参数            | 说明                 |
| ------------- | ------------------ |
| `--hostname`  | Master hostname    |
| `--port`      | base port          |
| `--dbpath`    | MongoDB database位置 |
| `--allowroot` | 允许root安装           |
| `--insecure`  | 忽略SSL错误            |
| `--yes`       | 自动确认               |

([CryoSPARC Guide][1])

---

# 6. Worker 安装

在 GPU 节点：

例如：

```
gpu001
```

安装：

```bash
./install.sh \
 --license $LICENSE_ID
```

然后连接：

```bash
cryosparcw connect \
 --worker gpu001 \
 --master master01 \
 --port 61000 \
 --ssdpath /scratch
```

---

参数：

| 参数          | 意义               |
| ----------- | ---------------- |
| `--worker`  | worker hostname  |
| `--master`  | master hostname  |
| `--port`    | master base port |
| `--ssdpath` | 本地SSD            |
| `--nossd`   | 无SSD             |
| `--cpus`    | worker CPU数      |
| `--sshstr`  | 自定义SSH           |

([CryoSPARC Guide][1])

---

# 7. Cluster 模式（Slurm / PBS）

适合：

* 大型 HPC
* GPU partition
* 多用户

结构：

```
                 Browser
                    |
              cryosparc_master
                    |
              cluster scheduler
                    |
          ----------------------
          |         |          |
       gpu001    gpu002     gpu003

             Slurm jobs

```

这里 worker 不是长期 daemon，而是：

```
CryoSPARC
    |
    |
cluster_script.sh
    |
    |
sbatch
    |
    |
GPU node
```

---

连接：

```bash
cryosparcm cluster connect
```

生成：

```
cluster_info.json
cluster_script.sh
```

---

典型 Slurm：

```bash
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
```

---

# 8. 端口整理

这是部署时最重要部分。

## 8.1 Base port

默认：

```
61000
```

用户访问：

```
http://master:61000
```

即：

```
Browser
 |
 TCP 61000
 |
Master Web UI
```

([CryoSPARC Guide][1])

---

# 8.2 Master 服务端口范围

CryoSPARC 会使用：

```
BASE_PORT + N
```

例如：

```
BASE_PORT=61000
```

可能使用：

```
61000
61001
61002
...
```

官方架构要求 worker 到 master：

```
10 consecutive ports
```

默认 worker 通信端口：

```
39000-39009
```

([CryoSPARC Guide][2])

---

## 8.3 防火墙规则

推荐：

```
Master:

TCP 61000-61009
        ^
        |
    workers


Browser:

TCP 61000
        ^
        |
    users
```

不要：

```
Internet
   |
61000
   |
CryoSPARC
```

官方建议 master 暴露端口不要直接暴露公网。([CryoSPARC Guide][1])

---

# 9. SSH 要求

Master → Worker：

必须：

```
ssh worker01
```

无需密码。

测试：

```bash
ssh gpu001 hostname
```

应该直接返回：

```
gpu001
```

配置：

```
~/.ssh/config

Host gpu*
    User cryosparc
    IdentityFile ~/.ssh/id_ed25519
```

---

# 10. 文件系统要求

推荐：

```
/shared

├── cryosparc_project
├── cryosparc_database
└── scratch
```

Master:

```
/shared/project
```

Worker:

```
/shared/project
```

必须一致。

原因：

Job产生的数据：

```
worker
 |
 write
 |
 shared filesystem
 |
 master读取
```

---

# 11. 推荐 HPC 部署方案（Slurm）

对于你已有 SLURM 集群，我建议：

```
login01
   |
   |
cryosparc_master
   |
   |
slurm
   |
------------------
gpu001 gpu002 gpu003

```

目录：

```
/share/apps/cryosparc
/share/projects/cryosparc
/share/scratch
```

Master:

```
CPU node
32G RAM
no GPU
```

Worker:

```
GPU node
A100/V100
local NVMe scratch
```

---

# 12. 常用管理命令

## Master

启动：

```bash
cryosparcm start
```

停止：

```bash
cryosparcm stop
```

状态：

```bash
cryosparcm status
```

日志：

```bash
cryosparcm logs
```

---

## Worker

状态：

```bash
cryosparcw connect
```

查看：

```bash
cryosparcw
```

---

# 13. 参数快速表

| 类别      | 参数                  | 作用        |
| ------- | ------------------- | --------- |
| 安装      | `--license`         | 授权        |
| 安装      | `--port`            | base port |
| Master  | `--hostname`        | master名字  |
| Master  | `--dbpath`          | 数据库位置     |
| Worker  | `--worker`          | worker名字  |
| Worker  | `--master`          | master地址  |
| Worker  | `--ssdpath`         | 本地SSD     |
| Worker  | `--cpus`            | CPU限制     |
| Cluster | `cluster connect`   | 连接调度器     |
| Cluster | `cluster_info.json` | 调度配置      |

---

如果按你已有的 **SLURM + GPU 节点 + Ansible 管理环境**，最佳实践通常不是 single workstation，而是：

```
cryosparc_master
        |
        |
 cryosparc cluster lane
        |
       Slurm
        |
 A100/V100 worker nodes
```

这样可以把 CryoSPARC 纳入现有账号、队列、GPU 资源管理。([CryoSPARC Guide][2])

[1]: https://guide.cryosparc.com/setup-configuration-and-management/how-to-download-install-and-configure/downloading-and-installing-cryosparc "Downloading and Installing CryoSPARC | CryoSPARC Guide"
[2]: https://guide.cryosparc.com/setup-configuration-and-management/hardware-and-system-requirements "CryoSPARC Architecture and System Requirements | CryoSPARC Guide"
