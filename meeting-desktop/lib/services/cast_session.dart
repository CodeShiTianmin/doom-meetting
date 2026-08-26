import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 推流模式(全部走 LiveKit 实时流)
enum CastMode { none, screen, video, camera }

/// 单房间推流会话(核心):
///
/// 每个房间一个独立的 CastSession = 独立 LiveKit RTC 连接(隐藏推流身份,
/// 只发不收) + 独立播放器 + 独立音视频轨。
/// 多房并发时各会话完全隔离, 天然不串音、不串频。
///
/// - 屏幕/窗口推流: getDisplayMedia 捕获整屏或指定窗口, 系统伴音走
///   WASAPI loopback (captureScreenAudio)
/// - 本地视频推流: media_kit 在房间页内直接解码播放(无独立窗口),
///   同时对本程序主窗口做窗口捕获推流; 播放器归会话持有, 页面关闭
///   不停止播放
/// - 摄像头推流: 直接采集本机摄像头推流
class CastSession extends ChangeNotifier {
  final int roomId;
  final String roomCode;

  CastSession({required this.roomId, required this.roomCode});

  lk.Room? _lkRoom;

  /// 本地视频播放器(页内播放, 归会话持有)
  Player? player;
  VideoController? videoController;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  CastMode mode = CastMode.none;

  /// 当前推流源名称(视频文件名/摄像头/屏幕源)
  String? sourceLabel;
  String? filePath;
  String? error;
  bool connected = false;
  bool publishing = false;

  /// 本地视频播放状态(本地视频推流模式)
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

  /// 本地视频推流: media_kit 在房间页内直接解码播放(不上传服务器),
  /// 同时捕获本程序主窗口以 LiveKit 实时流推给房间内手机端。
  Future<void> startVideoCast(String path) async {
    await stopCast();
    final participant = _requireParticipant();

    final mediaPlayer = Player();
    player = mediaPlayer;
    videoController = VideoController(mediaPlayer);
    _playingSub = mediaPlayer.stream.playing.listen((playing) {
      playerPlaying = playing;
      notifyListeners();
    });
    _positionSub = mediaPlayer.stream.position.listen((position) {
      playerPositionMs = position.inMilliseconds;
      notifyListeners();
    });
    _durationSub = mediaPlayer.stream.duration.listen((duration) {
      playerDurationMs = duration.inMilliseconds;
      notifyListeners();
    });

    try {
      await mediaPlayer.open(Media(path), play: true);
      final source = await _findMainWindowSource();
      await _publishCaptureTrack(participant, source.id);
    } catch (error) {
      await _disposePlayer();
      rethrow;
    }
    filePath = path;
    mode = CastMode.video;
    sourceLabel = path.split(RegExp(r'[\\/]')).last;
    publishing = true;
    notifyListeners();
  }

  /// 查找本程序主窗口作为捕获源; 找不到时回退整屏捕获
  Future<webrtc.DesktopCapturerSource> _findMainWindowSource() async {
    final sources = await listCaptureSources();
    final window = sources
        .where((source) => source.type == webrtc.SourceType.Window)
        .where((source) => source.name.contains('投屏会议'))
        .firstOrNull;
    if (window != null) return window;
    final screen = sources
        .where((source) => source.type == webrtc.SourceType.Screen)
        .firstOrNull;
    if (screen != null) return screen;
    throw StateError('未找到可捕获的窗口/屏幕, 无法推流');
  }

  /// 播放/暂停
  Future<void> playerPlayPause() async => player?.playOrPause();

  /// 跳转进度
  Future<void> playerSeek(int positionMs) async =>
      player?.seek(Duration(milliseconds: positionMs));

  Future<void> _disposePlayer() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    final mediaPlayer = player;
    player = null;
    videoController = null;
    playerPlaying = false;
    playerPositionMs = 0;
    playerDurationMs = 0;
    await mediaPlayer?.dispose();
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
    await _disposePlayer();
    filePath = null;
    sourceLabel = null;
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
