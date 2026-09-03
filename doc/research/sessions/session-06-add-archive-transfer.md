# Session 06：ADD、Archive 与镜像传输

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_faaa2ee7cffec9klaXQdFeLd9q` |
| 标题 | ADD --unpack=true |
| 时间 | 2026-08-31 01:09:17 至 10:14:25 UTC |
| 规模 | 234 messages，1480 parts，74 text parts |
| 审计状态 | 可见记录充分；大体积构建和 archive 输出按 manifest/error 摘要。 |

初始 user 锚点为 `prt_0555d11d9002qIga7vODegwHwo`。

## 已核实结果

- Podman 6.1.0 不支持 `ADD --unpack=true`；parser 原始错误为：

```text
ADD only supports --chmod=<permissions>, --chown=<uid:gid>, --checksum=<checksum>, --link, --keep-git-dir, and --exclude=<pattern> flags
```

- `ADD` 也没有 `--strip-components=1`；当前 Dockerfile 使用普通 tar `ADD` 和后续安装器布局处理。
- worker/patch archive 通过 boolean build ARG 选择，缺少未选择的可选 archive 时不会评估对应 stage。
- `COPY --exclude='pkg/*/**'` 用于排除 pkg 下的备份子目录；`-t/--tags` 和 root updater rename 属于构建辅助脚本的后续修订。
- 初始 `podman save` 未使用 `--multi-image-archive`，manifest 只有一个 entry；修复后 archive 约 `14.97 GB` 并包含三个 image entries。
- archive 文件逻辑大小接近不能证明内容相同，必须检查 `manifest.json` 和 config entries。

## 直接来源

- `containers/cryosparc5/Dockerfile:47-69` 记录 Podman parser 兼容写法和 `COPY --exclude`。
- `README.md:59-70` 记录三镜像 pack/extract 接口和输出文件。
- `doc/cryosparc-lifecycle-progress.md:221-230` 记录当前 optional package、target 和 transfer 脚本关系。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_0555d11d9002qIga7vODegwHwo` | user，2026-08-31 | 询问 `ADD --unpack=true`。 |
| `prt_05566cb38001nWfeX88UhUucHF` | assistant，2026-08-31 | parser 错误和替代方案。 |
| `prt_057368448001P70EbpklWNbyj9` | assistant，2026-08-31 | 单 entry archive 的根因。 |
| `prt_0573a3c1f001wdUvtGZXQ6kwDt` | assistant，2026-08-31 | multi-image 修复过程。 |
| `prt_0574f8c9d0014dr1Bo3t6gfW33` | assistant，2026-08-31 | 三 entry archive 结果。 |

## 完整性与限制

- `direct-source` 支持当前 Dockerfile 的 parser 规避方案。
- `runtime-observation` 支持 archive manifest 数量和 transfer helper 行为。
- `unresolved`：完整 CryoSPARC package build 的最终 digest、可重复性和大文件磁盘峰值未在本 session 完整测量。
- `unresolved`：archive 中包含镜像不等于目标 registry 已成功 push；push 权限需独立验证。
