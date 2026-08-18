# meeting_app — 手机客户端 (Flutter)

多房并发投屏会议系统的手机客户端。

## 功能

- 扫描 PC 端二维码（`meeting://join?roomCode=xxx&token=yyy`）或手动输入房号+一次性凭证匿名入会
- LiveKit(WebRTC) 观看 PC 隐藏推流；两客户音视频讨论（受 PC 端"视频通话/摄像头"开关控制）
- 播放控制：开始播放/暂停/拖拉进度条（两端共享同步，指令带序号防冲突）
- 明暗（屏幕亮度）与音量本地调节
- 会议已进行时长 + 剩余倒计时（剩余 5/1 分钟提醒，到期自动关闭）
- 点赞飘心并实时同步 PC 端记录
- 允许截屏、禁止录制：原生录屏检测（Android 15 ScreenRecordCallback / iOS isCaptured）→ 遮挡画面 → 上报后端；全屏身份+时间水印
- 心跳保活（10s），超时后端判定离线

## 运行

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://meeting.example.com \
  --dart-define=WS_URL=wss://meeting.example.com/ws
```

注：仓库仅包含核心工程文件（lib/、关键 android/ios 原生代码）。首次使用请在本目录执行 `flutter create . --org com.doommeeting --project-name meeting_app` 生成其余平台脚手架文件（不会覆盖已有文件的自定义内容时请留意合并 MainActivity/AppDelegate/Manifest/Info.plist）。
