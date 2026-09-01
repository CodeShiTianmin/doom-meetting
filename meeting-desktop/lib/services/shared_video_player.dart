import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// 统一推流共享播放器:
///
/// 全部房间共用这一个独立播放进程(后台窗口, 不弹出抢焦点/不进任务栏),
/// 各房间会话对同一窗口做窗口捕获推流 —— 20 个房间只解码播放一路视频,
/// 大幅降低多房并发时的显卡压力。
///
/// 推流后视频处于初始暂停状态, 由 PC 端或手机端统一控制播放/暂停/进度。
class SharedVideoPlayer extends ChangeNotifier {
  static const String windowTitle = '惊喜影视-统一推流';

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  ServerSocket? _controlServer;
  Socket? _controlSocket;
  StreamSubscription<String>? _controlSub;

  String? filePath;
  String? fileName;
  bool playing = false;
  int positionMs = 0;
  int durationMs = 0;
  bool started = false;

  /// 播放进程被外部关闭(如任务管理器结束)时回调, 用于同步停止统一推流
  Future<void> Function()? onClosedExternally;

  /// 播放状态变化回调(播放/暂停切换、进度跳变时触发,
  /// 用于向手机端广播统一播放状态)
  void Function(bool playing, int positionMs, int durationMs)?
      onPlayingChanged;

  DateTime? _lastBroadcastAt;
  int _lastBroadcastPositionMs = 0;

  /// 启动独立播放进程(初始暂停、后台窗口), 等待窗口就绪
  Future<void> start(String path) async {
    await close();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _controlServer = server;
    final ready = Completer<void>();
    server.listen((socket) {
      _controlSocket?.destroy();
      _controlSocket = socket;
      _controlSub?.cancel();
      _controlSub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleLine(line, ready),
              onError: (_) {}, cancelOnError: true);
    });
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'path': path,
      'title': windowTitle,
      'controlPort': server.port,
      'paused': true,
      'background': true,
    })));
    final process =
        await Process.start(Platform.resolvedExecutable, ['player', payload]);
    _process = process;
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleLine(line, ready));
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) => _onProcessExited(process)));

    try {
      await ready.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      await close();
      throw StateError('播放进程未就绪, 无法开始统一推流');
    }
    filePath = path;
    fileName = path.split(RegExp(r'[\\/]')).last;
    started = true;
    playing = false;
    _lastBroadcastAt = null;
    _lastBroadcastPositionMs = 0;
    notifyListeners();
  }

  /// 等待共享播放窗口出现在可捕获窗口列表中
  Future<webrtc.DesktopCapturerSource> waitWindowSource() async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final sources = await webrtc.desktopCapturer.getSources(
          types: [webrtc.SourceType.Window]);
      final source = sources
          .where((source) => source.name.contains(windowTitle))
          .firstOrNull;
      if (source != null) return source;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('播放窗口未就绪, 无法捕获推流');
  }

  Future<void> playOrPause() => _send({'cmd': 'playOrPause'});

  Future<void> seek(int positionMs) =>
      _send({'cmd': 'seekMs', 'value': positionMs});

  Future<void> routeAudio(List<String> keywords) =>
      _send({'cmd': 'audioRoute', 'keywords': keywords});

  void _handleLine(String line, Completer<void> ready) {
    if (!line.startsWith('@@player ')) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(line.substring('@@player '.length))
          as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (message['event']) {
      case 'ready':
        if (!ready.isCompleted) ready.complete();
        break;
      case 'state':
        _updateState(
          playing: message['playing'] as bool,
          positionMs: message['positionMs'] as int,
          durationMs: message['durationMs'] as int,
        );
        break;
    }
  }

  void _updateState(
      {required bool playing,
      required int positionMs,
      required int durationMs}) {
    final playingChanged = playing != this.playing;
    if (!playingChanged &&
        positionMs == this.positionMs &&
        durationMs == this.durationMs) {
      return;
    }
    this.playing = playing;
    this.positionMs = positionMs;
    this.durationMs = durationMs;
    notifyListeners();
    // 进度跳变(seek)的判定: 与上次广播后自然播放应达到的位置偏差过大
    final now = DateTime.now();
    final lastAt = _lastBroadcastAt;
    final elapsedMs =
        lastAt == null ? 0 : now.difference(lastAt).inMilliseconds;
    final expectedMs =
        _lastBroadcastPositionMs + (this.playing ? elapsedMs : 0);
    final seeked = (positionMs - expectedMs).abs() > 2000;
    if (playingChanged || seeked) {
      _lastBroadcastAt = now;
      _lastBroadcastPositionMs = positionMs;
      onPlayingChanged?.call(playing, positionMs, durationMs);
    } else {
      // 未广播时也跟进基准, 避免长时间播放后误判为 seek
      _lastBroadcastAt = now;
      _lastBroadcastPositionMs = positionMs;
    }
  }

  Future<void> _send(Map<String, dynamic> command) async {
    final line = jsonEncode(command);
    final socket = _controlSocket;
    if (socket != null) {
      try {
        socket.write('$line\n');
        await socket.flush();
        return;
      } catch (_) {}
    }
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(line);
      await process.stdin.flush();
    } catch (_) {
      // 播放进程已退出/未就绪时忽略
    }
  }

  Future<void> _onProcessExited(Process process) async {
    if (!identical(process, _process)) return;
    _process = null;
    await close();
    final callback = onClosedExternally;
    if (callback != null) await callback();
  }

  Future<void> close() async {
    final process = _process;
    _process = null;
    started = false;
    playing = false;
    positionMs = 0;
    durationMs = 0;
    filePath = null;
    fileName = null;
    _lastBroadcastAt = null;
    _lastBroadcastPositionMs = 0;
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    final socket = _controlSocket;
    if (process != null) {
      try {
        if (socket != null) {
          socket.write('${jsonEncode({'cmd': 'close'})}\n');
          await socket.flush();
        } else {
          process.stdin.writeln(jsonEncode({'cmd': 'close'}));
          await process.stdin.flush();
        }
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        process.kill();
      }
    }
    await _controlSub?.cancel();
    _controlSub = null;
    _controlSocket?.destroy();
    _controlSocket = null;
    await _controlServer?.close();
    _controlServer = null;
    notifyListeners();
  }
}
