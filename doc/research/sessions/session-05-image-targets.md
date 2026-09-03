# Session 05：镜像 Target 与静态构建

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_fb18b76b5ffeLixGi3lM09OFOH` |
| 标题 | 创建 master 与 workstation 两种 CryoSPARC 镜像 |
| 时间 | 2026-08-29 16:57:35 至 18:16:37 UTC |
| 规模 | 98 messages，642 parts，41 text parts |
| 审计状态 | 完整可见记录；用户明确只要求静态检查和 Podman dry-run。 |

初始 user 锚点为 `prt_04e7489a9001q94rfkXlCHcIU9`。

## 已核实结果

- 构建 stage 演化为公共 `master0`、cluster-only `master`、master+local worker 的 `workstation` 和同时含两者的 `hybrid`。
- `EXPOSE`、`ENTRYPOINT` 和公共 ENV 放在 `master0` 后由子 stage 继承，减少重复配置。
- 历史名称 `both` 已被 `hybrid` 取代；它描述镜像内容组合，不是第三种 CryoSPARC 产品安装方式。
- CryoSPARC archive 和 compiled binaries 面向 `linux/amd64`；ARM 主机需要 amd64 emulation。
- `bash -n`、`git diff --check`、Podman 参数检查和 build dry-run 通过。
- 用户明确未要求完整本地 build，因此本 session 没有把静态检查结果写成 full build 或 runtime smoke 证明。

## 直接来源

- `containers/cryosparc5/Dockerfile:5-9` 固定 CUDA、Ubuntu 和 amd64。
- `containers/cryosparc5/Dockerfile:127-171` 定义公共 `master0` 及三个最终 target。
- `README.md:38-57` 记录 target、tag 和 amd64 运行说明。
- `doc/cryosparc-lifecycle-progress.md:221-250` 汇总 target 与相关 commit 的历史关系。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_04e7489a9001q94rfkXlCHcIU9` | user，2026-08-29 | master/workstation 镜像目标和 Dockerfile 修改。 |
| `prt_04e9cea7d001zeTk3DJqNvVOsL` | assistant，2026-08-29 | target/stage 结构结论。 |
| `prt_04ebc937a001uc0YUrhh7UopyL` | assistant，2026-08-29 | 静态检查和平台参数结论。 |

## 完整性与限制

- `direct-source` 支持 stage 继承和 target 关系。
- `inference`：三个 target 的继承关系可从 Dockerfile 静态确认，但构建器具体缓存命中仍依赖上下文和本地 store。
- `unresolved`：没有本 session 的完整镜像 build，因此不能给出构建时间、实际 layer digest 或 runtime 服务结论。
