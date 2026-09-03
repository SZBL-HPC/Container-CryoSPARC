# 历史审计研究资料

本目录把 OpenCode 历史会话、当前仓库源码和指定测试环境的只读记录整理为可复查的研究资料。

审计截止时间为 2026-09-02。当前仓库 HEAD 为 `8f8671509ca8`，而部分早期文档是在较早的 `e9b6e8a` 快照上形成的；报告会明确区分历史快照和当前源码。

## 范围与边界

- 审计读取的 SQLite 数据库为 `/Users/galaxy/.local/share/opencode/opencode.db`。
- 审计没有读取或输出 `reasoningEncryptedContent`、真实 license、密码值或完整敏感 prompt。
- 远端验证仅限用户指定的 gpu14、login03 和已有容器/作业的只读检查。
- 没有为验证 GridView 额外提交 Slurm 作业，没有在 n5 中运行 `init`、`start` 或默认无参数入口。
- 没有在 macOS 执行包含完整 CryoSPARC 包的全量镜像构建。
- `ex/`、`pkg/` 和远端平台脚本可能不在代码图谱中；相关结论以直接源码、归档只读展开和运行记录为准。

## 证据等级

| 标记 | 含义 |
| --- | --- |
| `direct-source` | 当前工作区源码或文档中的可定位内容，引用包含文件和行号。 |
| `runtime-observation` | 指定测试主机、已有容器或已有作业的只读输出。 |
| `session-record` | SQLite 中的 user/assistant 可见 text part；part ID 可用于复查上下文。 |
| `inference` | 根据多个证据作出的解释，不等同于直接观测。 |
| `unresolved` | 当前证据不足，报告不把它写成事实。 |

## 文件索引

| 路径 | 内容 |
| --- | --- |
| `doc/official-sources.md` | CryoSPARC、Slurm、Docker/Podman 官方 URL 和本文档中的引用用途。 |
| `doc/research/sessions/` | 六个历史 session 的目标、时间线、证据锚点和完整性。 |
| `doc/research/gridview/README.md` | 镜像 lineage、GridView 启动链、runtime 参数和 URL prefix 问题。 |
| `doc/research/cryosparc-install/README.md` | standalone、分离 master/worker、cluster integration 和生命周期。 |
| `doc/research/slurm/README.md` | cluster 配置、master 地址、GRES、多 GPU 和失效 job。 |
| `doc/research/experiments/README.md` | live、smoke、n5、GridView 和 archive 验证记录。 |
| `doc/findings/verified-facts.md` | 去重后的直接事实及其来源。 |
| `doc/findings/inferences-and-open-questions.md` | 推断、置信度、未决问题和下一步验证边界。 |
| `doc/findings/doc-drift-and-gaps.md` | 历史路径、命名、版本和文档与实现的漂移。 |

## SQLite 引用规则

会话文件中的 `prt_...` 是 `part.id`，同时记录对应的 `message_id`、角色和时间时，引用才具有审计意义。assistant 的总结性 text part 不替代原始工具输出；工具输出过大或被摘要化时，报告引用当前研究文档中的已核实结论，并明确标记为限制。

六个 session 的总量为：

| Session | Message | Part | Text part |
| --- | ---: | ---: | ---: |
| `ses_033cafe22ffehnbHxUeAmN8k56` | 806 | 4558 | 305 |
| `ses_02f70f697ffeFPDB8zEDHIjDTg` | 234 | 1587 | 94 |
| `ses_ff277cf7fffe3gFpWyVwkSlZwd` | 633 | 3621 | 257 |
| `ses_fbf34f5a8ffeVmRjo46VLjtnyD` | 399 | 2523 | 120 |
| `ses_fb18b76b5ffeLixGi3lM09OFOH` | 98 | 642 | 41 |
| `ses_faaa2ee7cffec9klaXQdFeLd9q` | 234 | 1480 | 74 |

## 当前状态

六个历史 session 已完成有界审计并已形成会话文件。GridView 方面，已有作业 `787683` 的宿主侧 runtime 参数也已只读保存；仍未证明该次 GridView `docker run` 启动了 CryoSPARC 服务，也未从 n5 本地镜像元数据独立还原 push provenance。
