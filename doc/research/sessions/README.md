# 会话审计索引

本目录记录六个历史 OpenCode session。每个文件都区分 `direct-source`、`runtime-observation`、`session-record`、`inference` 和 `unresolved`，避免把历史 assistant 总结误当作当前实现。

| 文件 | Session | 主题 |
| --- | --- | --- |
| `session-01-install-docker-gridview.md` | `ses_033cafe22ffehnbHxUeAmN8k56` | 安装脚本、workstation 镜像、GridView URL、离线包和 live test。 |
| `session-02-fork-n5-gridview.md` | `ses_02f70f697ffeFPDB8zEDHIjDTg` | fork #1、历史 GridView 追踪和 n5/h1 只读核验。 |
| `session-03-cli-runtime-slurm.md` | `ses_ff277cf7fffe3gFpWyVwkSlZwd` | CLI 默认值、生命周期、license、Slurm 和失效 job。 |
| `session-04-network-hostname-pid.md` | `ses_fbf34f5a8ffeVmRjo46VLjtnyD` | hostname、动态 IPv4、Mongo、supervisor PID 和 `NO_PROXY`。 |
| `session-05-image-targets.md` | `ses_fb18b76b5ffeLixGi3lM09OFOH` | `master`、`workstation`、`hybrid` target 和静态构建核验。 |
| `session-06-add-archive-transfer.md` | `ses_faaa2ee7cffec9klaXQdFeLd9q` | `ADD` parser、可选 package、archive 和多镜像传输。 |

## 引用说明

每个 session 的 part 表只列出关键锚点，不复制敏感值或完整 prompt。精确查询方式是：

```sql
SELECT p.id, p.message_id, json_extract(m.data, '$.role'),
       p.time_created, json_extract(p.data, '$.text')
FROM part AS p
JOIN message AS m ON m.id = p.message_id
WHERE p.session_id = '<session-id>'
ORDER BY p.time_created, p.id;
```
