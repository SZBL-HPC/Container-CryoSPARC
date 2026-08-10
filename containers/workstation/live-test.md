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
- Password：`Passw0rd`

```bash
COOKIE_FILE="${TMPDIR:-/tmp}/cryosparc-cookies.txt"
PASSWORD_HASH="$(printf '%s' 'Passw0rd' | shasum -a 256 | cut -d' ' -f1)"

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
- 默认登录必须发送 SHA-256 后的密码；直接发送 `Passw0rd` 会得到 `Incorrect password`。
- 协议内容接口和静态 logo 文件都正常，问题不是文件缺失或服务未启动。
- 日志中曾出现 logo 首次请求被浏览器取消：`GET /CryoSPARC-logo-small@2x.png - -`，随后重新请求返回 `200`。手动打开图片后刷新页面能够显示，说明浏览器缓存命中了该资源；现象更接近首次请求取消或浏览器缓存/渲染问题。
