import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 独立本地视频播放窗口(子 Flutter 引擎):
///
/// 本地视频在此子窗口内解码播放, 主窗口对该子窗口做窗口捕获推流。
/// 播放与主窗口页面完全解耦 —— 主窗口切换到其他房间继续操作/推流时,
/// 各房间的播放窗口在后台持续播放, 互不影响。
///
/// 与主窗口的通信:
/// - 接收主窗口指令: playOrPause / seekMs / closePlayer
/// - 每 500ms 向主窗口(windowId=0)上报 playerState(播放/进度/时长)
/// - 窗口被关闭时上报 playerClosed, 主窗口据此停止对应房间推流
class PlayerWindowApp extends StatefulWidget {
  final int windowId;
  final Map<String, dynamic> params;

  const PlayerWindowApp(
      {super.key, required this.windowId, required this.params});

  @override
  State<PlayerWindowApp> createState() => _PlayerWindowAppState();
}

class _PlayerWindowAppState extends State<PlayerWindowApp> {
  late final Player _player;
  late final VideoController _videoController;
  Timer? _stateTimer;

  int get _roomId => widget.params['roomId'] as int;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _player.open(Media(widget.params['path'] as String), play: true);

    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      switch (call.method) {
        case 'playOrPause':
          await _player.playOrPause();
          break;
        case 'seekMs':
          await _player.seek(Duration(milliseconds: call.arguments as int));
          break;
        case 'closePlayer':
          await WindowController.fromWindowId(widget.windowId).close();
          break;
      }
      return null;
    });

    _stateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _reportState();
    });
  }

  Future<void> _reportState() async {
    try {
      await DesktopMultiWindow.invokeMethod(0, 'playerState', {
        'roomId': _roomId,
        'windowId': widget.windowId,
        'playing': _player.state.playing,
        'positionMs': _player.state.position.inMilliseconds,
        'durationMs': _player.state.duration.inMilliseconds,
      });
    } catch (_) {
      // 主窗口忙/未就绪时忽略, 下个周期重试
    }
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    // 尽力通知主窗口该播放窗口已关闭(如用户手动点了关闭按钮)
    DesktopMultiWindow.invokeMethod(0, 'playerClosed', {
      'roomId': _roomId,
      'windowId': widget.windowId,
    }).catchError((_) {});
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.params['title'] as String? ?? '投屏播放',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Video(controller: _videoController, controls: null),
      ),
    );
  }
}
