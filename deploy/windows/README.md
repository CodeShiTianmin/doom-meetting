# Windows 10/11 原生部署(无域名, 公网 IP 直连, 不依赖 Docker)

适用场景: 一台带公网 IP 的 Windows PC 直接当服务器, 没有域名, 运营商封了 80/443 入站(国内电信/联通家宽、商宽常见), 且不想装 Docker Desktop。

## 架构

全部组件以 **Windows 服务** 运行(开机自启、崩溃自动重启, 不依赖用户登录), 安装目录默认 `C:\doom-meeting`:

| 服务名 | 组件 | 对外端口 |
| --- | --- | --- |
| `DoomMeetingNginx` | Nginx 1.26: 管理后台静态页 + `/api` `/ws` 反代 | `NGINX_HTTP_PORT`(默认 8000)/tcp |
| `DoomMeetingServer` | meeting-server(Spring Boot, JDK 17) | 8080/tcp |
| `DoomMeetingMySQL` | MySQL 8.0 | 仅本机 127.0.0.1:3306 |
| `DoomMeetingLiveKit` | LiveKit SFU(内置 TURN) | 7880/tcp 7881/tcp 3478/udp 50000-50200/udp |

不用 Docker 的原因: `docker-compose.yml` 里 LiveKit 依赖 `network_mode: host` 向客户端通告真实 IP:端口, Docker Desktop for Windows 不支持 host 网络, bridge 映射会导致 WebRTC 媒体连接超时; 且 Docker Desktop 需要用户登录会话。

## 前置条件

- Windows 10 1809+ / Windows 11(自带 `curl.exe`、`tar.exe`), 管理员权限
- 本机能访问: 清华 TUNA 镜像、`cdn.mysql.com`、`nginx.org`、`gh-proxy.com`(GitHub 代理)、`maven.aliyun.com`、`registry.npmmirror.com`
- 已实测公网入站可达(例: `python -m http.server 8000` 后用手机流量访问 `http://<公网IP>:8000`)

无需预装 Java / Node / MySQL, 脚本会把 JDK、Maven、Node、MySQL、Nginx、LiveKit、WinSW 下载到 `C:\doom-meeting\downloads` 并解压到各自目录(便携式, 不写注册表、不改系统 PATH)。

## 步骤

以管理员打开 PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass        # 允许执行本地脚本(仅当前窗口)

cd <仓库目录>\deploy
Copy-Item .env.example .env
notepad .env        # 把 61.145.190.188 换成你的公网 IP; 改 MYSQL_ROOT_PASSWORD / APP_JWT_SECRET / LIVEKIT_API_SECRET / DEFAULT_ADMIN_PASSWORD

cd windows
.\install-native.ps1 -PublicIp <你的公网IP>
```

脚本步骤(`-Steps` 可只跑子集, 可重复执行):

| 步骤 | 内容 |
| --- | --- |
| `download` | 下载各组件(已存在则跳过) |
| `extract` | 解压; 安装 VC++ 2019 运行库(MySQL 依赖) |
| `mysql` | 初始化数据目录 → 注册服务 → 设置 root 密码 → 导入 `deploy/mysql/init.sql` |
| `build-server` | `mvn package`(阿里云镜像) → `C:\doom-meeting\server\app.jar` |
| `build-admin` | `npm ci && npm run build`(npmmirror) → `C:\doom-meeting\nginx\html` |
| `nginx` | 用 `deploy/nginx/nginx.conf` 的 server 块生成 Windows 版配置, 注册服务 |
| `livekit` | 生成 `livekit.yaml`(`node_ip` = 公网 IP), 注册服务 |
| `server` | 把 `.env` 写入服务环境变量, 注册服务(依赖 MySQL) |
| `firewall` | 放行上表端口(见 `setup-firewall.ps1`) |
| `power` | 禁止睡眠/休眠 |

完成后:

- 管理后台: `http://<公网IP>:8000` (账号见 `.env` 的 `DEFAULT_ADMIN_*`)
- 客户端打包(手机端 / PC 投屏端):
  ```bash
  --dart-define=API_BASE_URL=http://<公网IP>:8000 --dart-define=WS_URL=ws://<公网IP>:8000/ws
  ```
  App 已放行明文 HTTP(Android `usesCleartextTraffic` / iOS `NSAllowsArbitraryLoads`), 可直接用 `http://`。LiveKit 地址由服务端下发(`LIVEKIT_WS_URL`), 客户端无需配置。

## 日常运维

```powershell
Get-Service DoomMeeting*                                   # 状态
Restart-Service DoomMeetingServer                          # 重启后端
Get-Content C:\doom-meeting\server\DoomMeetingServer.out.log -Tail 100 -Wait   # 后端日志
Get-Content C:\doom-meeting\livekit\DoomMeetingLiveKit.out.log -Tail 100      # LiveKit 日志
Get-Content C:\doom-meeting\nginx\logs\error.log -Tail 50                     # Nginx 日志
Get-Content C:\doom-meeting\mysql-error.log -Tail 50                          # MySQL 日志

# 代码更新后只重新构建并重启
git pull
.\install-native.ps1 -Steps build-server,server            # 后端
.\install-native.ps1 -Steps build-admin,nginx              # 管理后台

# 修改 .env 后(端口/密钥)重新写入服务配置
.\install-native.ps1 -Steps nginx,livekit,server,firewall
```

服务日志由 WinSW 按大小滚动, 位于各服务目录下 `<服务名>.out.log` / `.err.log` / `.wrapper.log`。

## 让 Windows 适合长期当服务器

- 脚本已执行 `powercfg` 禁止睡眠/休眠。
- Windows 更新: 设置 → 更新 → 高级选项 → 设置"使用时段", 避免工作时间自动重启; 重启后所有服务会自动拉起。
- 建议固定 IP(向运营商确认是否静态); 动态 IP 需要 DDNS, 且每次变化后要更新 `.env` 的 `LIVEKIT_WS_URL` / `APP_CORS_ALLOWED_ORIGINS` 并执行 `-Steps livekit,server`。

## 安全提示

- 无 TLS: 管理后台密码、JWT 在网络上明文传输(音视频走 DTLS-SRTP 仍是加密的)。仅建议内部/试用; 正式对客户使用时加域名, 用 Cloudflare Tunnel 或 Nginx + 证书把 8000 包成 HTTPS, LiveKit 可继续走 IP。
- 生产前务必修改 `.env` 中的 `APP_JWT_SECRET`、`LIVEKIT_API_KEY/SECRET`、`MYSQL_ROOT_PASSWORD`、`DEFAULT_ADMIN_PASSWORD`, 并设 `APP_REJECT_DEFAULT_SECRETS=true`。
- 公网直连意味着 3389(远程桌面)、445(SMB)、22(SSH) 等全部暴露: 关闭不用的服务, 远程管理改用 Tailscale/VPN 或至少改端口 + 公钥/强密码。

## 排错

| 现象 | 处理 |
| --- | --- |
| 手机端连接超时 `MediaConnectException` | `Get-NetFirewallRule -DisplayName "DoomMeeting*"` 确认规则存在; 检查 `C:\doom-meeting\livekit\livekit.yaml` 的 `node_ip` 是否为公网 IP; 路由器/光猫若在前面做了 NAT 需再做端口映射 |
| 管理后台能开, 登录报网络错误 | 看后端日志; 确认 `.env` 的 `NGINX_HTTP_PORT` 与访问端口一致 |
| `DoomMeetingServer` 反复重启 | 多为数据库连不上或 `APP_REJECT_DEFAULT_SECRETS=true` 但仍用默认密钥, 看 `DoomMeetingServer.out.log` |
| 某个下载失败 | 浏览器手动下载对应文件, 按脚本内 `$downloads` 的文件名放入 `C:\doom-meeting\downloads` 后重跑 |
| MySQL 初始化失败 | 确认 VC++ 2019 x64 运行库已安装; 删除 `C:\doom-meeting\mysql-data` 后重跑 `-Steps mysql` |
