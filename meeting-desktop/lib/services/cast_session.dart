import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// 推流模式(全部走 LiveKit 实时流)
enum CastMode { none, screen, video, camera }

/// 单房间推流会话(核心):
///
/// 每个房间一个独立的 CastSession = 独立 LiveKit RTC 连接(隐藏推流身份,
/// 只发不收) + 独立播放窗口 + 独立音视频轨。
/// 多房并发时各会话完全隔离, 天然不串音、不串频。
///
/// - 屏幕/窗口推流: getDisplayMedia 捕获整屏或指定窗口, 系统伴音走
///   回环采集设备(立体声混音/虚拟声卡)单独发布音频轨
/// - 本地视频推流: 每房间启动一个独立播放进程(重启自身 exe, media_kit
///   解码), 对该进程窗口做窗口捕获推流; 播放与主进程页面完全解耦,
///   主窗口切到其他房间操作时后台持续播放推流。必须用独立进程:
///   WebRTC 的窗口枚举会过滤本进程自己的窗口, 同进程子窗口无法捕获
/// - 摄像头推流: 直接采集本机摄像头推流
class CastSession extends ChangeNotifier {
  final int roomId;
  final String roomCode;

  CastSession({required this.roomId, required this.roomCode});

  lk.Room? _lkRoom;
  Process? _playerProcess;
  StreamSubscription<String>? _playerStdoutSub;

  /// 播放窗口被用户手动关闭时的回调(用于同步服务端推流登记)
  Future<void> Function()? onPlayerClosedExternally;

  CastMode mode = CastMode.none;

  /// 当前推流源名称(视频文件名/摄像头/屏幕源)
  String? sourceLabel;
  String? filePath;
  String? error;
  bool connected = false;
  bool publishing = false;

  /// 系统伴音采集失败时的提示(推流仅有画面无声音)
  String? audioCaptureWarning;

  /// 独立播放窗口上报的播放状态(本地视频推流模式)
  bool playerPlaying = false;
  int playerPositionMs = 0;
  int playerDurationMs = 0;

  /// 连接 LiveKit(隐藏推流身份)
  Future<void> connect(String wsUrl, String token) async {
    if (connected) return;
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: false,
        dynacast: true,
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          // 高清 1080p/30fps, 最高 6Mbps 自适应, simulcast 多档分辨率
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 6 * 1000 * 1000,
            maxFramerate: 30,
          ),
          simulcast: true,
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          maxFrameRate: 30,
          params: lk.VideoParameters(
            dimensions: lk.VideoDimensionsPresets.h1080_169,
            encoding: lk.VideoEncoding(
              maxBitrate: 6 * 1000 * 1000,
              maxFramerate: 30,
            ),
          ),
        ),
      ),
    );
    await room.connect(wsUrl, token);
    _lkRoom = room;
    connected = true;
    notifyListeners();
  }

  /// 枚举可捕获的屏幕/窗口源
  Future<List<webrtc.DesktopCapturerSource>> listCaptureSources() {
    return webrtc.desktopCapturer.getSources(
        types: [webrtc.SourceType.Screen, webrtc.SourceType.Window]);
  }

  /// 屏幕/窗口推流: 捕获整屏或指定窗口推流, 系统伴音走回环采集
  Future<void> startScreenCast(webrtc.DesktopCapturerSource source) async {
    await stopCast();
    final participant = _requireParticipant();
    await _publishCaptureTrack(participant, source.id);
    final loopback = await _publishSystemAudioTrack(participant);
    if (loopback != null && _playbackRouteKeywords(loopback.label) != null) {
      // 虚拟声卡输出端只能采到路由进其输入端的声音;
      // 屏幕推流无法代为路由, 需系统默认播放设备指向虚拟声卡
      audioCaptureWarning =
          '已从虚拟声卡「${loopback.label}」采集伴音; 若推流无声音, '
          '请将系统默认播放设备设为该虚拟声卡的输入端(如 CABLE Input)';
    }
    mode = CastMode.screen;
    sourceLabel = source.name;
    publishing = true;
    notifyListeners();
  }

  /// 摄像头推流: 采集本机摄像头画面 + 麦克风声音推流
  Future<void> startCameraCast({String? deviceId, String? label}) async {
    await stopCast();
    final participant = _requireParticipant();
    final videoTrack = await lk.LocalVideoTrack.createCameraTrack(
      lk.CameraCaptureOptions(
        deviceId: deviceId,
        params: const lk.VideoParameters(
          // 高清 1080p 摄像头推流
          dimensions: lk.VideoDimensionsPresets.h1080_169,
          encoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
        ),
      ),
    );
    try {
      await participant.publishVideoTrack(videoTrack);
    } catch (error) {
      await videoTrack.stop();
      rethrow;
    }
    try {
      final audioTrack =
          await lk.LocalAudioTrack.create(const lk.AudioCaptureOptions());
      await participant.publishAudioTrack(audioTrack);
    } catch (_) {
      // 无麦克风或采集失败时仅推画面
    }
    mode = CastMode.camera;
    sourceLabel = label ?? '摄像头';
    publishing = true;
    notifyListeners();
  }

  /// 创建并发布屏幕捕获轨: 部分环境不支持系统伴音回环采集,
  /// 失败时回退为仅画面投屏; 发布失败时停止轨道避免泄漏捕获会话
  Future<void> _publishCaptureTrack(
      lk.LocalParticipant participant, String sourceId) async {
    lk.LocalVideoTrack track;
    try {
      track = await lk.LocalVideoTrack.createScreenShareTrack(
        lk.ScreenShareCaptureOptions(
          sourceId: sourceId,
          captureScreenAudio: true,
          maxFrameRate: 30,
          params: const lk.VideoParameters(
            dimensions: lk.VideoDimensionsPresets.h1080_169,
            encoding: lk.VideoEncoding(
              maxBitrate: 6 * 1000 * 1000,
              maxFramerate: 30,
            ),
          ),
        ),
      );
    } catch (_) {
      track = await lk.LocalVideoTrack.createScreenShareTrack(
        lk.ScreenShareCaptureOptions(
          sourceId: sourceId,
          captureScreenAudio: false,
          maxFrameRate: 30,
          params: const lk.VideoParameters(
            dimensions: lk.VideoDimensionsPresets.h1080_169,
            encoding: lk.VideoEncoding(
              maxBitrate: 6 * 1000 * 1000,
              maxFramerate: 30,
            ),
          ),
        ),
      );
    }
    try {
      await participant.publishVideoTrack(track);
    } catch (error) {
      await track.stop();
      rethrow;
    }
  }

  /// Windows 桌面端 getDisplayMedia 不携带系统声音(captureScreenAudio 仅浏览器
  /// 生效), 屏幕/本地视频推流需从回环采集设备(立体声混音/虚拟声卡)单独采集
  /// 系统伴音并作为音频轨发布; 找不到设备时仅推画面并给出提示。
  /// 返回成功采集的回环设备(未采到时返回 null)。
  ///
  /// 按关键字优先级选择: 立体声混音类设备直接采集默认扬声器输出,
  /// 无需路由, 优先使用; 虚拟声卡(VB-CABLE/Voicemeeter)只能采到
  /// 路由进其输入端的声音, 本地视频推流时由播放进程定向路由。
  Future<lk.MediaDevice?> _publishSystemAudioTrack(
      lk.LocalParticipant participant) async {
    audioCaptureWarning = null;
    const loopbackKeywords = [
      '立体声混音',
      '立體聲混音',
      'stereo mix',
      'what u hear',
      'what you hear',
      'wave out',
      'loopback',
      'cable output',
      'voicemeeter out',
      'virtual audio',
    ];
    lk.MediaDevice? loopback;
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      for (final keyword in loopbackKeywords) {
        for (final device in inputs) {
          if (device.label.toLowerCase().contains(keyword)) {
            loopback = device;
            break;
          }
        }
        if (loopback != null) break;
      }
    } catch (_) {}
    if (loopback == null) {
      audioCaptureWarning =
          '未找到系统伴音采集设备, 推流将没有声音。请在系统声音设置中启用「立体声混音」, '
          '或安装 VB-CABLE 等虚拟声卡后重新推流';
      return null;
    }
    try {
      final audioTrack = await lk.LocalAudioTrack.create(lk.AudioCaptureOptions(
        deviceId: loopback.deviceId,
        // 采集的是音乐/影片伴音, 关闭人声处理避免声音被消除或压制
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        voiceIsolation: false,
        typingNoiseDetection: false,
      ));
      await participant.publishAudioTrack(audioTrack);
      return loopback;
    } catch (error) {
      audioCaptureWarning = '系统伴音采集失败, 推流将没有声音: $error';
      return null;
    }
  }

  /// 回环采集设备为虚拟声卡输出端时, 返回其配对播放端(输入端)的关键字,
  /// 用于将播放进程音频路由过去; 立体声混音类设备采集默认输出,
  /// 无需路由, 返回 null
  List<String>? _playbackRouteKeywords(String inputLabel) {
    final label = inputLabel.toLowerCase();
    if (label.contains('cable output')) return const ['cable input'];
    if (label.contains('voicemeeter out')) {
      return const ['voicemeeter input', 'voicemeeter aux input'];
    }
    if (label.contains('virtual audio')) return const ['virtual audio'];
    return null;
  }

  /// 本地视频推流: 启动独立播放进程本地解码播放(不上传服务器),
  /// 对该进程窗口做窗口捕获以 LiveKit 实时流推给房间内手机端。
  /// 播放进程独立于主窗口, 切换房间/页面不影响后台推流。
  Future<void> startVideoCast(String path) async {
    await stopCast();
    final participant = _requireParticipant();

    final title = '投屏播放-$roomCode';
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'roomId': roomId,
      'path': path,
      'title': title,
    })));
    final process = await Process.start(
        Platform.resolvedExecutable, ['player', payload]);
    _playerProcess = process;
    final ready = Completer<void>();
    _playerStdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handlePlayerLine(line, ready));
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) => _onPlayerProcessExited(process)));

    try {
      await ready.future.timeout(const Duration(seconds: 15));
      final source = await _waitPlayerWindowSource(title);
      await _publishCaptureTrack(participant, source.id);
      final loopback = await _publishSystemAudioTrack(participant);
      if (loopback != null) {
        // 采集的是虚拟声卡输出端时, 把播放进程声音路由到其配对输入端,
        // 否则播放声音走默认扬声器, 虚拟声卡采到的是静音
        final routeKeywords = _playbackRouteKeywords(loopback.label);
        if (routeKeywords != null) {
          await _sendPlayerCommand(
              {'cmd': 'audioRoute', 'keywords': routeKeywords});
        }
      }
    } catch (error) {
      await _closePlayerWindow();
      if (error is TimeoutException) {
        throw StateError('播放窗口未就绪, 无法捕获推流');
      }
      rethrow;
    }
    filePath = path;
    mode = CastMode.video;
    sourceLabel = path.split(RegExp(r'[\\/]')).last;
    publishing = true;
    notifyListeners();
  }

  /// 等待播放进程窗口出现在可捕获窗口列表中(独立进程窗口可正常枚举)
  Future<webrtc.DesktopCapturerSource> _waitPlayerWindowSource(
      String title) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final sources = await listCaptureSources();
      final source = sources
          .where((source) => source.type == webrtc.SourceType.Window)
          .where((source) => source.name.contains(title))
          .firstOrNull;
      if (source != null) return source;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('播放窗口未就绪, 无法捕获推流');
  }

  void _handlePlayerLine(String line, Completer<void> ready) {
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
        _updatePlayerState(
          playing: message['playing'] as bool,
          positionMs: message['positionMs'] as int,
          durationMs: message['durationMs'] as int,
        );
        break;
      case 'audioRoute':
        if (message['ok'] != true) {
          audioCaptureWarning =
              '播放声音未能路由到虚拟声卡, 推流可能没有声音。'
              '请将系统默认播放设备设为虚拟声卡输入端(如 CABLE Input)';
          notifyListeners();
        }
        break;
    }
  }

  /// 播放/暂停(转发给独立播放进程)
  Future<void> playerPlayPause() => _sendPlayerCommand({'cmd': 'playOrPause'});

  /// 跳转进度(转发给独立播放进程)
  Future<void> playerSeek(int positionMs) =>
      _sendPlayerCommand({'cmd': 'seekMs', 'value': positionMs});

  Future<void> _sendPlayerCommand(Map<String, dynamic> command) async {
    final process = _playerProcess;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode(command));
      await process.stdin.flush();
    } catch (_) {
      // 播放进程已退出/未就绪时忽略
    }
  }

  /// 接收播放进程周期性上报的播放状态
  void _updatePlayerState(
      {required bool playing,
      required int positionMs,
      required int durationMs}) {
    if (playing == playerPlaying &&
        positionMs == playerPositionMs &&
        durationMs == playerDurationMs) {
      return;
    }
    playerPlaying = playing;
    playerPositionMs = positionMs;
    playerDurationMs = durationMs;
    notifyListeners();
  }

  /// 播放进程退出(如用户手动关窗): 同步停止本房间推流并登记服务端
  Future<void> _onPlayerProcessExited(Process process) async {
    if (!identical(process, _playerProcess)) return;
    _playerProcess = null;
    final wasVideoCast = mode == CastMode.video;
    await stopCast();
    final callback = onPlayerClosedExternally;
    if (wasVideoCast && callback != null) await callback();
  }

  Future<void> _closePlayerWindow() async {
    final process = _playerProcess;
    _playerProcess = null;
    playerPlaying = false;
    playerPositionMs = 0;
    playerDurationMs = 0;
    await _playerStdoutSub?.cancel();
    _playerStdoutSub = null;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode({'cmd': 'close'}));
      await process.stdin.flush();
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      process.kill();
    }
  }

  /// 未连接时直接报错, 避免静默跳过推流却显示投屏中的"假成功"
  lk.LocalParticipant _requireParticipant() {
    final participant = connected ? _lkRoom?.localParticipant : null;
    if (participant == null) {
      throw StateError('媒体服务未连接, 无法推流');
    }
    return participant;
  }

  /// 停止推流: 任一环节失败/超时不阻塞后续清理, 保证本地状态一定复位
  Future<void> stopCast() async {
    final participant = _lkRoom?.localParticipant;
    if (participant != null) {
      for (final publication in participant.trackPublications.values.toList()) {
        try {
          await participant
              .removePublishedTrack(publication.sid)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    }
    await _closePlayerWindow();
    filePath = null;
    sourceLabel = null;
    audioCaptureWarning = null;
    mode = CastMode.none;
    publishing = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await stopCast();
    await _lkRoom?.disconnect();
    await _lkRoom?.dispose();
    _lkRoom = null;
    connected = false;
    notifyListeners();
  }
}
