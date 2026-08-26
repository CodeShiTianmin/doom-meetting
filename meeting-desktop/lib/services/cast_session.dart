import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
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
///   WASAPI loopback (captureScreenAudio)
/// - 本地视频推流: 每房间开一个独立播放窗口(子 Flutter 引擎, media_kit
///   解码), 对该窗口做窗口捕获推流; 播放与主窗口页面解耦, 主窗口切到
///   其他房间操作时后台持续播放推流
/// - 摄像头推流: 直接采集本机摄像头推流
class CastSession extends ChangeNotifier {
  final int roomId;
  final String roomCode;

  CastSession({required this.roomId, required this.roomCode});

  lk.Room? _lkRoom;
  int? _playerWindowId;

  CastMode mode = CastMode.none;

  /// 当前推流源名称(视频文件名/摄像头/屏幕源)
  String? sourceLabel;
  String? filePath;
  String? error;
  bool connected = false;
  bool publishing = false;

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

  /// 本地视频推流: 开独立播放窗口本地解码播放(不上传服务器),
  /// 对该窗口做窗口捕获以 LiveKit 实时流推给房间内手机端。
  /// 播放窗口独立于主窗口, 切换房间/页面不影响后台推流。
  Future<void> startVideoCast(String path) async {
    await stopCast();
    final participant = _requireParticipant();

    final title = '投屏播放-$roomCode';
    final window = await DesktopMultiWindow.createWindow(jsonEncode({
      'roomId': roomId,
      'path': path,
      'title': title,
    }));
    _playerWindowId = window.windowId;
    await window.setTitle(title);
    await window.setFrame(const Rect.fromLTWH(120, 120, 960, 560));
    await window.show();

    try {
      final source = await _waitPlayerWindowSource(title);
      await _publishCaptureTrack(participant, source.id);
    } catch (error) {
      await _closePlayerWindow();
      rethrow;
    }
    filePath = path;
    mode = CastMode.video;
    sourceLabel = path.split(RegExp(r'[\\/]')).last;
    publishing = true;
    notifyListeners();
  }

  /// 等待播放窗口出现在可捕获窗口列表中(子引擎启动需要时间)
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

  /// 播放/暂停(转发给独立播放窗口)
  Future<void> playerPlayPause() => _invokePlayerWindow('playOrPause');

  /// 跳转进度(转发给独立播放窗口)
  Future<void> playerSeek(int positionMs) =>
      _invokePlayerWindow('seekMs', positionMs);

  Future<void> _invokePlayerWindow(String method, [dynamic arguments]) async {
    final windowId = _playerWindowId;
    if (windowId == null) return;
    try {
      await DesktopMultiWindow.invokeMethod(windowId, method, arguments);
    } catch (_) {
      // 播放窗口已关闭/未就绪时忽略
    }
  }

  /// 接收播放窗口周期性上报的播放状态
  void updatePlayerState(
      {required int windowId,
      required bool playing,
      required int positionMs,
      required int durationMs}) {
    if (windowId != _playerWindowId) return;
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

  /// 播放窗口被外部关闭(如用户手动关窗): 同步停止本房间推流
  Future<void> onPlayerWindowClosed(int windowId) async {
    if (windowId != _playerWindowId) return;
    _playerWindowId = null;
    await stopCast();
  }

  Future<void> _closePlayerWindow() async {
    final windowId = _playerWindowId;
    _playerWindowId = null;
    playerPlaying = false;
    playerPositionMs = 0;
    playerDurationMs = 0;
    if (windowId == null) return;
    try {
      await WindowController.fromWindowId(windowId).close();
    } catch (_) {
      // 窗口已关闭时忽略
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
