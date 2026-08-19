# 多房并发投屏会议系统 (doom-meetting)

方案设计公司将本地 PC 上的方案视频资料投屏到会议房间，客户在手机端观看并进行语音/视频讨论；公司方不参与讨论。

## 模块

| 目录 | 说明 | 技术栈 |
| --- | --- | --- |
| `meeting-server/` | 后台业务 + 信令 | Java 17 + Spring Boot 3 + MySQL 8 + Spring Security(JWT) + WebSocket(STOMP) |
| `meeting-admin/` | 公司管理系统(PC 端) | Vite + React 18 + Material UI |
| `meeting-app-flutter/` | 手机客户端 App | Flutter 3 + livekit_client + STOMP |
| `meeting-desktop/` | 公司 PC 投屏端(Windows) | Flutter Desktop + livekit_client + flutter_webrtc + media_kit |
| `deploy/` | 一键部署 | Docker Compose(Nginx + Spring Boot + LiveKit + coturn + MySQL) |

## 核心功能

- **房间模型**：单房间成员数可设置（默认 2 个手机客户端）；公司 PC 端以后台隐藏身份推流与管理（LiveKit hidden publisher），不出现在房间成员中。
- **会议功能开关**：手机端"视频通话/摄像头"功能由 PC 端按房间设置开放或关闭，实时下发生效。
- **多房并发投放**：仅支持两种投放方式——上传文件投放（文件存服务器，会议结束后自动删除）与 PC 屏幕/窗口共享（LiveKit 直接推流）；投放前检查已有投放，需先停止当前投放再投放新内容；每房间独立 SFU Room + 独立音视频轨，不串音、不串频（支持定时投放计划）。
- **就位与播放控制**：全部手机客户端就位后房间进入"已运行"并开始会议计时；手机端可 开始播放/暂停/拖拉进度条（指令带序号、后端串行转发防两端冲突）；PC 端可全量控制手机端播放（播放/暂停/进度/明暗/音量，PC 指令为权威指令）。
- **会议时间**：房间显示已进行时长与剩余倒计时；PC 端可设置会议时长，剩余 5 分钟/1 分钟推送提醒，到期自动关闭房间。
- **点赞**：手机端点赞按钮实时推送 PC 端展示并入库记录。
- **截屏/防录制**：允许截屏、禁止录制——不使用 FLAG_SECURE，采用录屏检测 + 遮挡上报 + 全屏水印方案。
- **缺人红灯预警**：创建房间后缺人状态超过 3 分钟（可配置），后台亮红灯预警；心跳超时自动判定离线。

## 快速开始

```bash
# 后端 (需 JDK 17 + MySQL 8)
cd meeting-server && mvn spring-boot:run

# 管理端 (http://localhost:5173, 默认账号 admin/admin123)
cd meeting-admin && npm install && npm run dev

# 手机端 (Flutter, 支持 Android/iOS)
cd meeting-app-flutter && flutter pub get && flutter run \
  --dart-define=API_BASE_URL=http://<后端地址>:8080 \
  --dart-define=WS_URL=ws://<后端地址>:8080/ws

# PC 投屏端 (Flutter Desktop / Windows)
cd meeting-desktop && flutter pub get && flutter run -d windows \
  --dart-define=API_BASE_URL=http://<后端地址>:8080 \
  --dart-define=WS_URL=ws://<后端地址>:8080/ws

# 或 Docker Compose 一键部署
cd deploy && docker compose up -d
```

## 安全设计

全链路 HTTPS/WSS；媒体流 WebRTC DTLS-SRTP 加密；SFU 关闭录制/转推；上传的投放文件仅在会议期间保存在服务器，会议结束（房间关闭）后自动删除；一次性入会凭证（短时效 + 绑定房间 + 限用次数）；房间人数硬限制（成员数上限可按房间设置，默认 2）；文件下载需短时效签名 token 或管理员 JWT；WebSocket 订阅需管理员 JWT（admin topic）或房间成员身份（房间 topic）。

生产环境务必通过环境变量覆盖默认密钥（`APP_JWT_SECRET`、`LIVEKIT_API_KEY/LIVEKIT_API_SECRET`、`DEFAULT_ADMIN_PASSWORD`），并设置 `APP_REJECT_DEFAULT_SECRETS=true` 强制启动校验；同时用 `APP_CORS_ALLOWED_ORIGINS` 限定管理网页域名。

## 部署约束

后端并发控制依赖 JVM 内锁（`synchronized`），调度器无分布式锁，**仅支持单实例部署**。如需多实例横向扩展，需先引入数据库乐观锁/分布式锁（如 ShedLock）。
