# Session 01：安装、镜像与 GridView

## 元数据

| 项目 | 值 |
| --- | --- |
| Session | `ses_033cafe22ffehnbHxUeAmN8k56` |
| 标题 | 分析安装脚本与 Docker 镜像制作方案 |
| 时间 | 2026-08-04 09:57:33 至 2026-08-10 03:17:55 UTC |
| 规模 | 806 messages，4558 parts，305 text parts |
| 审计状态 | 可见记录充分；大型工具输出按结论和关键错误摘要。 |

用户最初要求结合 `install.md`、解压安装包和补丁包分析三种部署场景，并优先制作 workstation 镜像。对应 user 锚点为 `prt_fcc350228001vJLPd5lh5Mh9Le`。

## 时间线与结果

- 安装研究先形成 `install-analysis.md`，把产品安装方式归纳为 standalone workstation 与分离 master/worker 两种；cluster/Slurm 被识别为非-standalone master 上的后续 integration。
- workstation Dockerfile 使用本地 `pkg/` archive 和 bundled dependencies，构建阶段使用占位 license，真实 license 延迟到 runtime。
- 容器 lifecycle 逐步收敛为 `entrypoint` 启动 sshd，`cryosparc` 负责 `init/start/status`，CryoSPARC 服务由 supervisord daemon 化，entrypoint 自己用 sleep 保活。
- `6080/ai-forward/<id>/` 的 GridView URL 前缀导致 CryoSPARC 页面生成的 root-absolute `/assets/*`、`/api/*` 和 WebSocket 路径落到错误位置；问题不是 gzip 或资源缺失。
- Web 资源在 master 的 `app/custom-server/dist/client` 中，未发现需要浏览器从 Google/CDN 下载的依赖。
- live test 验证了容器内 `61000`、外部 HTTP、登录 cookie、协议接口和资源请求；外部 prefix 访问仍不适合直接承载 CryoSPARC root-absolute Web 应用。

## 直接来源

- `install-analysis.md:12-18,80-229` 记录安装模式、master/worker 脚本调用链及 cluster integration 边界。
- `install-analysis.md:231-360` 记录补丁包、patch metadata URL 和 `master`/`worker` mode 限制。
- `install-analysis.md:362-410` 区分安装阶段 `--nogpu` 与 connect 阶段 `--no-gpu`。
- `README.md:8-23,38-73` 记录当前 target、amd64、rootless、runtime license 和 archive 传输规则。
- `README.md:93-145` 记录 entrypoint、命令、runtime config、worker/cluster 注册和 reset/warmup 行为。
- `containers/cryosparc5/Dockerfile:5-39,43-125,127-156` 记录当前构建阶段、可选 package、临时数据库和最终 target 基础层。
- `containers/cryosparc5/entrypoint:5-35` 记录 sshd、CryoSPARC wrapper 和保活循环。
- `containers/cryosparc5/live-test.md:13-47,175-218` 记录登录协议、测速、资源请求和 HTTP 结果。

## Session part 锚点

| Part | 角色/时间 | 用途 |
| --- | --- | --- |
| `prt_fcc350228001vJLPd5lh5Mh9Le` | user，2026-08-04 | 初始安装分析和 workstation 镜像目标。 |
| `prt_fd06c16da001PD7vGGBPOPkoL9` | assistant，2026-08-05 | 安装、SSH、HTTP/HTTPS 调查阶段总结。 |
| `prt_fd117255a001B0jGoZbNKJ5rpy` | assistant，2026-08-05 | workstation Dockerfile 和离线依赖阶段总结。 |
| `prt_fd18c5526001MGZlXavCULdWHo` | assistant，2026-08-05 | runtime、locale、API、GridView 和 live test 阶段总结。 |
| `prt_fe9acfdad001GdvMiHqPMor38M` | assistant，2026-08-10 | live test 文档完成和提交前状态。 |

这些 assistant part 是可见总结锚点，不替代被摘要的原始 tool output。当前结论以仓库文件和 `live-test.md` 的可定位记录为主。

## 证据等级与限制

- `direct-source`：安装模式、当前 Dockerfile target、entrypoint 和 Web 路径行为有文件级来源。
- `runtime-observation`：live 容器的服务状态、HTTP 响应、登录和资源请求来自指定测试记录。
- `inference`：GridView prefix 与 CryoSPARC root-absolute 路径的因果解释由多次请求失败和成功路径归纳，不能推广到所有代理实现。
- `unresolved`：当时没有完整还原 GridView 平台最终 `docker run` 参数，也没有证明容器入口在该平台上启动 CryoSPARC 服务。
- `unresolved`：该 session 使用的安装包文档版本和当前 `pkg/` v5.0.7 不能混用；版本差异见 `doc/findings/doc-drift-and-gaps.md`。
