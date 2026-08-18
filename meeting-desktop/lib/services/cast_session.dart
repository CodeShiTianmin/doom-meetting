import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 投放模式
enum CastMode { none, screen, file }

/// 单房间投放会话(核心):
///
/// 每个房间一个独立的 CastSession = 独立 LiveKit RTC 连接(隐藏推流身份,
/// 只发不收) + 独立 media_kit 播放器实例 + 独立音视频轨。
/// 多房并发时各会话完全隔离, 天然不串音、不串频。
///
/// - 屏幕/窗口投屏: getDisplayMedia 捕获整屏或指定窗口, 系统伴音走
///   WASAPI loopback (captureScreenAudio)
/// - 本地文件投放: media_kit 解码播放, 支持响应手机端的
///   开始播放/暂停/拖拉进度条指令(权威状态由后端广播)
class CastSession extends ChangeNotifier {
  final int roomId;
  final String roomCode;

  CastSession({required this.roomId, required this.roomCode});

  lk.Room? _lkRoom;
  Player? _player;
  VideoController? _videoController;

  CastMode mode = CastMode.none;
  String? filePath;
  String? error;
  bool connected = false;
  bool publishing = false;

  Player? get player => _player;
  VideoController? get videoController => _videoController;

  /// 连接 LiveKit(隐藏推流身份)
  Future<void> connect(String wsUrl, String token) async {
    if (connected) return;
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: false,
        dynacast: true,
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          // 1080p/30fps, 2-4Mbps 自适应, simulcast 多档分辨率
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
          simulcast: true,
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

  /// 屏幕/窗口投屏: 捕获整屏或指定窗口推流, 系统伴音走回环采集
  Future<void> startScreenCast(webrtc.DesktopCapturerSource source) async {
    await stopCast();
    final track = await lk.LocalVideoTrack.createScreenShareTrack(
      lk.ScreenShareCaptureOptions(
        sourceId: source.id,
        captureScreenAudio: true,
        maxFrameRate: 30,
      ),
    );
    await _lkRoom?.localParticipant?.publishVideoTrack(track);
    mode = CastMode.screen;
    publishing = true;
    notifyListeners();
  }

  /// 媒体文件投放: media_kit 解码播放(文件同时上传服务器保存, 会议结束后删除),
  /// 播放画面经独立播放器窗口捕获推流; 手机端播放控制指令直接作用于该播放器
  Future<void> startFileCast(String path,
      {required webrtc.DesktopCapturerSource playerWindowSource}) async {
    await stopCast();
    filePath = path;
    _player = Player();
    _videoController = VideoController(_player!);
    await _player!.open(Media(path), play: false);

    final track = await lk.LocalVideoTrack.createScreenShareTrack(
      lk.ScreenShareCaptureOptions(
        sourceId: playerWindowSource.id,
        captureScreenAudio: true,
        maxFrameRate: 30,
      ),
    );
    await _lkRoom?.localParticipant?.publishVideoTrack(track);
    mode = CastMode.file;
    publishing = true;
    notifyListeners();
  }

  /// 手机端播放控制指令(经后端信令转发, 权威状态由后端广播)
  Future<void> applyPlaybackCommand(Map<String, dynamic> data) async {
    if (mode != CastMode.file || _player == null) return;
    final action = data['action'] as String?;
    switch (action) {
      case 'PLAY':
        await _player!.play();
        break;
      case 'PAUSE':
        await _player!.pause();
        break;
      case 'SEEK':
        final position = (data['positionSeconds'] as num?)?.toDouble() ?? 0;
        await _player!
            .seek(Duration(milliseconds: (position * 1000).round()));
        break;
      default:
        break;
    }
  }

  Future<void> stopCast() async {
    final participant = _lkRoom?.localParticipant;
    if (participant != null) {
      for (final publication in participant.trackPublications.values.toList()) {
        await participant.removePublishedTrack(publication.sid);
      }
    }
    await _player?.dispose();
    _player = null;
    _videoController = null;
    filePath = null;
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
