# CryoSPARC 与 GridView 调查资料

本目录整理截至 2026-09-02 的源码分析、历史会话审计、远端只读调查和 gpu14 隔离 smoke。

文档有意分成两类：`research/` 保留研究过程、证据和实验边界；`findings/` 只保留去重后的事实、推断、未决问题和文档缺口。
这样可以在部门 MkDocs 中分别展示“做过什么”和“最终确认了什么”。

## 推荐阅读顺序

1. [已核实事实](findings/verified-facts.md)：先看可以直接引用的事实和证据位置。
2. [推断与未决问题](findings/inferences-and-open-questions.md)：区分高置信度解释和不能继续推断的部分。
3. [CryoSPARC 安装与生命周期](research/cryosparc-install/README.md)：了解安装方式、`init`、`start`、worker 和 cluster 的调用关系。
4. [GridView 研究](research/gridview/README.md)：了解镜像、Slurm Prolog、容器入口、mount、ENV 和 `787683` 作业取证。
5. [Slurm 与 Cluster 研究](research/slurm/README.md)：了解地址职责、GRES/cgroup、多 GPU、license 和 scheduler target。
6. [实验与验证记录](research/experiments/README.md)：查看哪些内容经过 smoke、哪些内容没有在生产环境验证。
7. [六个历史会话](research/sessions/README.md)：按 session 查看研究来源、时间线和完整性边界。

## 文档索引

| 分类 | 文件 | 内容 |
| --- | --- | --- |
| 入口 | `doc/README.md` | 本目录说明和阅读路径。 |
| 官方引用 | [official-sources.md](official-sources.md) | CryoSPARC、Slurm、Docker/Podman 官方 URL 和引用用途。 |
| 研究 | [research/README.md](research/README.md) | 审计范围、证据等级、六个 session 的总量和研究文件索引。 |
| 研究 | [research/cryosparc-install/README.md](research/cryosparc-install/README.md) | 两种产品安装方式、容器 target、安装过程、`init`、`start`、license、patch 和 GPU。 |
| 研究 | [research/gridview/README.md](research/gridview/README.md) | GridView 镜像 lineage、Slurm 启动链、runtime command、mount、ENV 和 URL prefix。 |
| 研究 | [research/slurm/README.md](research/slurm/README.md) | CryoSPARC cluster 配置、master 地址、Slurm GRES/cgroup、多 GPU和 stale job。 |
| 研究 | [research/experiments/README.md](research/experiments/README.md) | gpu14、live、n5、h1、Slurm 和 archive 实验矩阵。 |
| 研究 | [research/sessions/README.md](research/sessions/README.md) | 六个历史 OpenCode session 的审计索引。 |
| 结论 | [findings/verified-facts.md](findings/verified-facts.md) | F-001 至 F-022 的可核实事实。 |
| 结论 | [findings/inferences-and-open-questions.md](findings/inferences-and-open-questions.md) | I-001 至 I-006、Q-001 至 Q-007 和禁止过度推断的边界。 |
| 结论 | [findings/doc-drift-and-gaps.md](findings/doc-drift-and-gaps.md) | 路径、版本、端口、实现和历史文档的漂移及验证缺口。 |

## 会话交接文件

以下文件是三个短子任务在超时前后的交接记录，不替代 `research/` 和 `findings/` 中的正式资料：

- [GridView 进度交接](gridview-progress.md)
- [CryoSPARC 生命周期进度交接](cryosparc-lifecycle-progress.md)
- [历史会话审计进度交接](history-audit-progress.md)

## 证据规则

- `direct-source` 表示当前仓库源码或文档中的可定位内容。
- `runtime-observation` 表示指定主机、已有容器或已有作业的只读输出。
- `session-record` 表示 OpenCode SQLite 中可见的 user/assistant 文本和审计锚点。
- `inference` 表示由多个证据推导的解释，不等同于直接观测。
- `unresolved` 表示现有证据不足，不能写成确定事实。

真实 license、密码、SSH 私钥和完整敏感 prompt 不写入这些文档。
远端实验没有提交或取消新的生产作业，也没有执行会破坏数据的 reset 操作。
