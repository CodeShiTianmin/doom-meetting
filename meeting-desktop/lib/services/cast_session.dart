import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_loopback_pool.dart';

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
  ServerSocket? _controlServer;
  Socket? _controlSocket;
  StreamSubscription<String>? _controlSub;

  /// 播放窗口被用户手动关闭时的回调(用于同步服务端推流登记)
  Future<void> Function()? onPlayerClosedExternally;

  CastMode mode = CastMode.none;

  /// 当前推流源名称(视频文件名/摄像头/屏幕源)
  String? sourceLabel;
  String? filePath;
  String? error;
  bool connected = false;
  bool publishing = false;

  /// 当前发布的视频轨(屏幕/本地视频/摄像头), 供房间页面内嵌预览
  lk.LocalVideoTrack? localVideoTrack;

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
          // 高清 1080p/30fps; 1080p30 屏幕/视频内容 4Mbps 已接近主观清晰度
          // 上限, 码率再高只会挤占手机下行带宽造成卡顿
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
          simulcast: true,
          // H264 走硬件编码: 多房并发时大幅降低 CPU/GPU 占用,
          // 避免软编 VP8 算力不足时出现条纹/色块等编码伪影
          videoCodec: 'H264',
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          maxFrameRate: 30,
          params: lk.VideoParameters(
            dimensions: lk.VideoDimensionsPresets.h1080_169,
            encoding: lk.VideoEncoding(
              maxBitrate: 4 * 1000 * 1000,
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

  /// 屏幕/窗口推流: 捕获整屏或指定窗口推流。伴音优先随画面一起用
  /// Windows 系统回环采集(无需虚拟声卡); 不支持时回退回环设备采集
  Future<void> startScreenCast(webrtc.DesktopCapturerSource source) async {
    await stopCast();
    final participant = _requireParticipant();
    final hasCaptureAudio = await _publishCaptureTrack(participant, source.id);
    if (!hasCaptureAudio) {
      final channel =
          await _publishSystemAudioTrack(participant, preferDedicated: false);
      if (channel != null && channel.dedicated) {
        // 虚拟声卡输出端只能采到路由进其输入端的声音;
        // 屏幕推流无法代为路由, 需系统默认播放设备指向虚拟声卡
        audioCaptureWarning = '已从虚拟声卡「${channel.device.label}」采集伴音; 若推流无声音, '
            '请将系统默认播放设备设为该虚拟声卡的输入端(如 CABLE Input)';
      } else if (channel != null && _sharedWithOthers(channel)) {
        audioCaptureWarning = '多个房间正在共用同一伴音采集设备, 声音会互相串音。'
            '建议安装多条 VB-CABLE 虚拟声卡(CABLE A/B)实现每房间独立伴音';
      }
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
            maxBitrate: 3 * 1000 * 1000,
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
    localVideoTrack = videoTrack;
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

  /// 创建并发布屏幕捕获轨。Windows 上随画面同时用 WASAPI 回环采集
  /// 伴音: 捕获窗口时只采该窗口所属进程的声音(按进程隔离, 多房间
  /// 天然不串音, 需 Win10 2004+), 捕获整屏时采全系统声音。
  /// 返回是否成功发布了伴音轨; 失败时回退为仅画面,
  /// 由调用方再走回环设备采集。发布失败时停止轨道避免泄漏捕获会话
  Future<bool> _publishCaptureTrack(
      lk.LocalParticipant participant, String sourceId) async {
    final options = lk.ScreenShareCaptureOptions(
      sourceId: sourceId,
      maxFrameRate: 30,
      params: const lk.VideoParameters(
        dimensions: lk.VideoDimensionsPresets.h1080_169,
        encoding: lk.VideoEncoding(
          maxBitrate: 4 * 1000 * 1000,
          maxFramerate: 30,
        ),
      ),
    );
    lk.LocalVideoTrack videoTrack;
    lk.LocalAudioTrack? audioTrack;
    try {
      final tracks =
          await lk.LocalVideoTrack.createScreenShareTracksWithAudio(options);
      videoTrack = tracks.whereType<lk.LocalVideoTrack>().first;
      audioTrack = tracks.whereType<lk.LocalAudioTrack>().firstOrNull;
    } catch (_) {
      videoTrack = await lk.LocalVideoTrack.createScreenShareTrack(options);
    }
    localVideoTrack = videoTrack;
    try {
      // 顶层 1080p30/4Mbps 独立满码率编码, 另发 720p/360p 全帧率低档层:
      // 手机下行带宽不足时 SFU 自动切低档层保持流畅, 带宽充足时始终收
      // 顶层高清; 低档层保持 30fps 避免视频内容切档后掉帧卡顿。
      // 发送端带宽/性能不足时优先保帧率(降分辨率), 避免卡顿
      await participant.publishVideoTrack(
        videoTrack,
        publishOptions: const lk.VideoPublishOptions(
          simulcast: true,
          videoCodec: 'H264',
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
          screenShareSimulcastLayers: [
            lk.VideoParameters(
              dimensions: lk.VideoDimensionsPresets.h360_169,
              encoding: lk.VideoEncoding(
                maxBitrate: 800 * 1000,
                maxFramerate: 30,
              ),
            ),
            lk.VideoParameters(
              dimensions: lk.VideoDimensionsPresets.h720_169,
              encoding: lk.VideoEncoding(
                maxBitrate: 2200 * 1000,
                maxFramerate: 30,
              ),
            ),
          ],
          // 保分辨率: 编码器算力/带宽吃紧时降帧率而非动态缩放分辨率,
          // 非整数比例缩放屏幕/视频内容会产生横向条纹状锟齿波纹
          degradationPreference: lk.DegradationPreference.maintainResolution,
        ),
      );
    } catch (error) {
      await videoTrack.stop();
      await audioTrack?.stop();
      rethrow;
    }
    if (audioTrack == null) return false;
    try {
      await participant.publishAudioTrack(audioTrack);
      return true;
    } catch (_) {
      await audioTrack.stop();
      return false;
    }
  }

  /// Windows 桌面端 getDisplayMedia 不携带系统声音(captureScreenAudio 仅浏览器
  /// 生效), 屏幕/本地视频推流需从回环采集设备(立体声混音/虚拟声卡)单独采集
  /// 系统伴音并作为音频轨发布; 找不到设备时仅推画面并给出提示。
  /// 返回成功采集的回环设备(未采到时返回 null)。
  ///
  /// 通道由 AudioLoopbackPool 按房间分配: 本地视频推流优先独占虚拟声卡
  /// 通道(每房间一条, 互不串音), 屏幕推流优先立体声混音(采集默认输出)。
  Future<LoopbackChannel?> _publishSystemAudioTrack(
      lk.LocalParticipant participant,
      {required bool preferDedicated}) async {
    audioCaptureWarning = null;
    final channel = await AudioLoopbackPool.instance
        .acquire(roomId, preferDedicated: preferDedicated);
    if (channel == null) {
      audioCaptureWarning = '未找到系统伴音采集设备, 推流将没有声音。请在系统声音设置中启用「立体声混音」, '
          '或安装 VB-CABLE 等虚拟声卡后重新推流';
      return null;
    }
    try {
      final audioTrack = await lk.LocalAudioTrack.create(lk.AudioCaptureOptions(
        deviceId: channel.device.deviceId,
        // 采集的是音乐/影片伴音, 关闭人声处理避免声音被消除或压制
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        voiceIsolation: false,
        typingNoiseDetection: false,
      ));
      await participant.publishAudioTrack(audioTrack);
      return channel;
    } catch (error) {
      AudioLoopbackPool.instance.release(roomId);
      audioCaptureWarning = '系统伴音采集失败, 推流将没有声音: $error';
      return null;
    }
  }

  bool _sharedWithOthers(LoopbackChannel channel) => AudioLoopbackPool.instance
      .sharedWithOtherRooms(roomId, channel.device.deviceId);

  /// 本地视频推流: 启动独立播放进程本地解码播放(不上传服务器),
  /// 对该进程窗口做窗口捕获以 LiveKit 实时流推给房间内手机端。
  /// 播放进程独立于主窗口, 切换房间/页面不影响后台推流。
  Future<void> startVideoCast(String path) async {
    await stopCast();
    final participant = _requireParticipant();

    final title = '投屏播放-$roomCode';
    // 控制通道走本地回环 TCP: Windows GUI 子进程的 stdin 管道在部分
    // 环境下不可靠, 导致播放/暂停/进度指令无法送达播放进程
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
          .listen((line) => _handlePlayerLine(line, ready),
              onError: (_) {}, cancelOnError: true);
    });
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'roomId': roomId,
      'path': path,
      'title': title,
      'controlPort': server.port,
    })));
    final process =
        await Process.start(Platform.resolvedExecutable, ['player', payload]);
    _playerProcess = process;
    _playerStdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handlePlayerLine(line, ready));
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) => _onPlayerProcessExited(process)));

    try {
      await ready.future.timeout(const Duration(seconds: 15));
      final source = await _waitPlayerWindowSource(title);
      // 捕获播放窗口时伴音按进程隔离采集: 只采本房间播放进程的声音,
      // 多房间并发天然互不串音, 无需虚拟声卡
      final hasCaptureAudio =
          await _publishCaptureTrack(participant, source.id);
      if (!hasCaptureAudio) {
        final channel =
            await _publishSystemAudioTrack(participant, preferDedicated: true);
        if (channel != null && channel.dedicated) {
          // 把播放进程声音定向路由到本房间独占的虚拟声卡输入端,
          // 否则播放声音走默认扬声器, 虚拟声卡采到的是静音
          await _sendPlayerCommand(
              {'cmd': 'audioRoute', 'keywords': channel.routeKeywords});
        } else if (channel != null && _sharedWithOthers(channel)) {
          audioCaptureWarning = '虚拟声卡通道不足, 本房间与其他房间共用伴音采集, 声音会互相串音。'
              '建议加装 VB-CABLE A/B 等虚拟声卡实现每房间独立伴音';
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
          audioCaptureWarning = '播放声音未能路由到虚拟声卡, 推流可能没有声音。'
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
    final line = jsonEncode(command);
    final socket = _controlSocket;
    if (socket != null) {
      try {
        socket.write('$line\n');
        await socket.flush();
        return;
      } catch (_) {}
    }
    final process = _playerProcess;
    if (process == null) return;
    try {
      process.stdin.writeln(line);
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
        final track = publication.track;
        try {
          await participant
              .removePublishedTrack(publication.sid)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        // 确保底层采集会话一定停止: 否则取消推流后屏幕/窗口捕获
        // 仍在后台运行, 多房并发时持续占用显卡与 CPU
        try {
          await track?.stop();
        } catch (_) {}
      }
    }
    await _closePlayerWindow();
    AudioLoopbackPool.instance.release(roomId);
    localVideoTrack = null;
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
