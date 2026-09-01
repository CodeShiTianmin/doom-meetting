import 'package:flutter/foundation.dart';

import '../models/room.dart';
import 'api_client.dart';
import 'cast_session.dart';
import 'shared_video_player.dart';

/// 统一推流管理(单例):
///
/// 全部固定房间(1-20)共用同一路推流内容 —— 任一房间发起本地视频推流,
/// 其余房间同步推同一内容。实现方式:
/// - 一个共享播放进程(后台窗口, 初始暂停)解码播放视频
/// - 每个房间一个 CastSession(独立 LiveKit 连接), 全部捕获同一共享窗口
/// - 播放/暂停/进度由 PC 端或手机端统一控制, 状态广播到全部手机端
class CastManager extends ChangeNotifier {
  CastManager._();

  static final CastManager instance = CastManager._();

  final Map<int, CastSession> _sessions = {};

  /// 共享播放器(统一推流进行中时非空)
  SharedVideoPlayer? player;

  /// 当前统一推流的视频文件名(未推流时为空)
  String? get castFileName => player?.fileName;

  bool get casting => player != null && player!.started;

  CastSession? sessionOf(int roomId) => _sessions[roomId];

  Iterable<CastSession> get sessions => _sessions.values;

  /// 获取或创建房间投放会话(懒连接: 首次使用时申请隐藏推流 Token 并连接)
  Future<CastSession> ensureSession(int roomId) async {
    final existing = _sessions[roomId];
    if (existing != null && existing.connected) return existing;

    final tokenInfo = await ApiClient.instance.getPublisherToken(roomId);
    final session = existing ??
        CastSession(roomId: roomId, roomCode: tokenInfo['roomCode'] as String);
    _sessions[roomId] = session;
    try {
      await session.connect(
        tokenInfo['livekitWsUrl'] as String,
        tokenInfo['livekitToken'] as String,
      );
    } catch (_) {
      // 连接失败的会话不留在缓存, 避免后续复用失败实例
      _sessions.remove(roomId);
      session.dispose();
      rethrow;
    }
    return session;
  }

  /// 统一推流: 启动共享播放进程(初始暂停), 全部未关闭房间捕获同一窗口推流。
  /// 返回推流失败的房号列表(单房失败不中断其余房间)。
  Future<List<String>> startUnifiedVideoCast(
      String path, List<RoomModel> rooms) async {
    await stopUnifiedCast(notifyServer: false);

    final sharedPlayer = SharedVideoPlayer();
    player = sharedPlayer;
    sharedPlayer.onClosedExternally = () async {
      if (identical(player, sharedPlayer)) {
        await stopUnifiedCast();
      }
    };
    // 播放状态变化(播放/暂停)同步广播到全部手机端
    sharedPlayer.onPlayingChanged = (playing, positionMs, durationMs) {
      ApiClient.instance
          .broadcastPlayback(
              playing: playing,
              positionMs: positionMs,
              durationMs: durationMs)
          .catchError((_) {});
    };
    sharedPlayer.addListener(notifyListeners);

    try {
      await sharedPlayer.start(path);
      final source = await sharedPlayer.waitWindowSource();
      final failed = <String>[];
      for (final room in rooms) {
        if (room.closed) continue;
        try {
          final session = await ensureSession(room.id);
          await session.startWindowCast(source,
              label: sharedPlayer.fileName);
        } catch (_) {
          failed.add(room.roomCode);
        }
      }
      await ApiClient.instance
          .startCastAll('VIDEO', label: sharedPlayer.fileName);
      notifyListeners();
      return failed;
    } catch (error) {
      await stopUnifiedCast(notifyServer: false);
      rethrow;
    }
  }

  /// 停止统一推流: 关闭共享播放进程并停止全部房间的捕获轨
  Future<void> stopUnifiedCast({bool notifyServer = true}) async {
    final sharedPlayer = player;
    player = null;
    if (sharedPlayer != null) {
      sharedPlayer.onClosedExternally = null;
      sharedPlayer.onPlayingChanged = null;
      sharedPlayer.removeListener(notifyListeners);
      await sharedPlayer.close();
      sharedPlayer.dispose();
    }
    for (final session in _sessions.values) {
      try {
        await session.stopCast();
      } catch (_) {}
    }
    if (notifyServer) {
      try {
        await ApiClient.instance.stopCastAll();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 手机端播放控制指令(经服务端 WS 转发到 PC 端执行)
  Future<void> handleRemoteControl(Map<String, dynamic> payload) async {
    final sharedPlayer = player;
    if (sharedPlayer == null || !sharedPlayer.started) return;
    switch (payload['action']) {
      case 'playOrPause':
        await sharedPlayer.playOrPause();
        break;
      case 'seek':
        final positionMs = (payload['positionMs'] as num?)?.toInt();
        if (positionMs != null) await sharedPlayer.seek(positionMs);
        break;
    }
  }

  Future<void> closeSession(int roomId) async {
    final session = _sessions.remove(roomId);
    await session?.disconnect();
    session?.dispose();
  }

  Future<void> closeAll() async {
    await stopUnifiedCast(notifyServer: false);
    for (final roomId in _sessions.keys.toList()) {
      try {
        await closeSession(roomId);
      } catch (_) {
        // 单个房间清理失败不中断其余房间清理
      }
    }
  }
}
