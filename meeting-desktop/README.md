# meeting_desktop — PC 投屏端 (Flutter Desktop / Windows)

多房并发投屏会议系统的公司 PC 投屏端。以后台隐藏身份推流(只发不收)，不出现在房间成员中。

## 功能

- 公司账号登录(JWT)
- 创建房间(会议时长、视频通话/摄像头开关)、生成邀请二维码(`meeting://join?...`)
- 多房并发投放：每房间独立 LiveKit RTC 连接 + 独立 media_kit 播放器实例 + 独立音视频轨，不串音不串频
- 屏幕/窗口投屏(getDisplayMedia，系统伴音 WASAPI loopback)
- 文件投放(所有类型)：真实文件上传服务器保存，媒体文件 media_kit 解码推流，其他类型系统应用打开后窗口投屏；会议结束后服务器文件自动删除；支持打开服务器上的当前投放文件
- 响应手机端 播放/暂停/拖进度条 指令(STOMP 信令，权威状态由后端广播)
- 房间就位/已运行提示、缺人红灯预警、点赞实时展示、录屏行为告警
- 手动结束会议/到期自动关闭

## 运行

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows \
  --dart-define=API_BASE_URL=https://meeting.example.com \
  --dart-define=WS_URL=wss://meeting.example.com/ws
```

注：仓库仅包含核心工程文件(lib/)。首次使用请在本目录执行 `flutter create . --platforms=windows --org com.doommeeting --project-name meeting_desktop` 生成 Windows 平台脚手架。
