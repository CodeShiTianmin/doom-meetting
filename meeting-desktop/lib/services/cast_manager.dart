import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

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

  /// 当前统一推流捕获的共享播放窗口(未推流时为空)
  webrtc.DesktopCapturerSource? _source;

  /// 正在同步推流状态的房间 id, 避免周期刷新重入
  final Set<int> _syncing = {};

  /// 统一推流启动中(逐房发布未完成), 期间不做房间状态同步
  bool _starting = false;

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
    final wsUrl = tokenInfo['livekitWsUrl'] as String?;
    final token = tokenInfo['livekitToken'] as String?;
    if (wsUrl == null || wsUrl.isEmpty || token == null || token.isEmpty) {
      throw StateError('服务端未返回媒体服务连接信息');
    }
    final session = existing ??
        CastSession(
            roomId: roomId,
            roomCode: (tokenInfo['roomCode'] as String?) ?? '$roomId');
    if (existing == null) {
      // 会话状态(连接/推流/错误)变化同步通知页面刷新
      session.addListener(notifyListeners);
    }
    _sessions[roomId] = session;
    try {
      await session.connect(wsUrl, token);
    } catch (_) {
      // 连接失败的会话不留在缓存, 避免后续复用失败实例
      _sessions.remove(roomId);
      session.removeListener(notifyListeners);
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

    _starting = true;
    try {
      await sharedPlayer.start(path);
      final source = await sharedPlayer.waitWindowSource();
      _source = source;
      final failed = <String>[];
      var succeeded = 0;
      for (final room in rooms) {
        if (room.closed) continue;
        try {
          await _castToRoom(room.id, source, sharedPlayer.fileName);
          succeeded++;
        } catch (_) {
          failed.add(room.roomCode);
        }
      }
      if (succeeded == 0) {
        throw StateError(failed.isEmpty
            ? '没有可推流的房间(全部房间已关闭)'
            : '全部房间推流失败, 请检查媒体服务连接');
      }
      await ApiClient.instance
          .startCastAll('VIDEO', label: sharedPlayer.fileName);
      notifyListeners();
      return failed;
    } catch (error) {
      await stopUnifiedCast(notifyServer: false);
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _castToRoom(
      int roomId, webrtc.DesktopCapturerSource source, String? label) async {
    final session = await ensureSession(roomId);
    await session.startWindowCast(source, label: label);
  }

  /// 按总览最新房间状态同步统一推流:
  /// - 已关闭的房间停止捕获推流, 释放编码资源
  /// - 重置/恢复的房间(服务端已登记推流但本地未发布)重新加入统一推流
  Future<void> syncRooms(List<RoomModel> rooms) async {
    final sharedPlayer = player;
    final source = _source;
    if (_starting ||
        sharedPlayer == null ||
        !sharedPlayer.started ||
        source == null) {
      return;
    }
    for (final room in rooms) {
      if (!identical(player, sharedPlayer)) return;
      final session = _sessions[room.id];
      if (room.closed) {
        if (session != null && session.publishing) {
          try {
            await session.stopCast();
          } catch (_) {}
        }
        continue;
      }
      if (!room.casting || (session?.publishing ?? false)) continue;
      if (!_syncing.add(room.id)) continue;
      try {
        await _castToRoom(room.id, source, sharedPlayer.fileName);
      } catch (_) {
        // 单房重新加入失败不影响其余房间, 下次刷新重试
      } finally {
        _syncing.remove(room.id);
      }
    }
  }

  /// 停止统一推流: 关闭共享播放进程并停止全部房间的捕获轨
  Future<void> stopUnifiedCast({bool notifyServer = true}) async {
    final sharedPlayer = player;
    player = null;
    _source = null;
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
    if (session == null) return;
    session.removeListener(notifyListeners);
    await session.disconnect();
    session.dispose();
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
