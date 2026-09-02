import 'package:flutter/foundation.dart';

import '../models/room.dart';
import 'api_client.dart';
import 'cast_session.dart';
import 'room_video_player.dart';

/// 房间推流管理(单例):
///
/// 每个房间独立设置视频文件、独立推流、独立播放控制, 互不影响:
/// - 「设置文件」只记录该房间要推的本地视频路径, 本身不启动推流
///   (总览的「统一设置文件」只是把同一文件批量设置到各房间,
///   进入单房页面后自动开始推流)
/// - 「开始推流」启动该房间的播放进程(暂停在 0 秒)并发布到该房间
/// - 播放/暂停/进度由 PC 端或该房间手机端控制, 状态只广播到该房间
/// - 停止推流后关闭播放进程(进度归零), 已设置的文件保留
/// - 房间退出(结束会议重置/关闭/会议结束回到空闲)时停止推流并初始化状态,
///   已设置的文件保留, 下次进入该房间可直接推流
class CastManager extends ChangeNotifier {
  CastManager._();

  static final CastManager instance = CastManager._();

  final Map<int, CastSession> _sessions = {};

  /// 各房间已设置的本地视频文件路径(停止推流/房间退出均不清除)
  final Map<int, String> _videoFiles = {};

  /// 各房间上次同步到的服务端状态, 用于识别“房间退出”的状态跃迁
  final Map<int, String> _lastStatus = {};

  /// 正在启动/停止推流的房间 id, 防止重入与周期刷新误停
  final Set<int> _transitioning = {};

  /// 各房间最近一次开始推流的时间: 服务端登记后短时间内总览刷新可能仍是
  /// 登记前的旧数据, 宽限期内不按旧数据误停本地推流
  final Map<int, DateTime> _castStartedAt = {};

  static const Duration _syncGrace = Duration(seconds: 20);

  CastSession? sessionOf(int roomId) => _sessions[roomId];

  Iterable<CastSession> get sessions => _sessions.values;

  /// 房间已设置的视频文件路径
  String? videoFileOf(int roomId) => _videoFiles[roomId];

  /// 房间已设置的视频文件名(完整文件名)
  String? videoFileNameOf(int roomId) {
    final path = _videoFiles[roomId];
    return path == null ? null : fileNameOf(path);
  }

  static String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

  /// 房间本地是否正在推流
  bool isCasting(int roomId) => _sessions[roomId]?.publishing ?? false;

  /// 房间正在推流的播放器(未推流时为空)
  RoomVideoPlayer? playerOf(int roomId) => _sessions[roomId]?.player;

  /// 是否有任一房间正在推流
  bool get anyCasting => _sessions.values.any((s) => s.publishing);

  bool isTransitioning(int roomId) => _transitioning.contains(roomId);

  /// 设置房间视频文件(仅记录, 不推流)
  void setVideoFile(int roomId, String path) {
    _videoFiles[roomId] = path;
    notifyListeners();
  }

  /// 清空房间已设置的视频文件
  void clearVideoFile(int roomId) {
    if (_videoFiles.remove(roomId) != null) notifyListeners();
  }

  /// 批量设置视频文件到多个房间(仅记录, 不推流)。
  /// 正在推流的房间跳过不改, 返回被跳过的房号
  List<String> setVideoFileForRooms(Iterable<RoomModel> rooms, String path) {
    final skipped = <String>[];
    for (final room in rooms) {
      if (room.closed) continue;
      if (isCasting(room.id)) {
        skipped.add(room.roomCode);
        continue;
      }
      _videoFiles[room.id] = path;
    }
    notifyListeners();
    return skipped;
  }

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

  /// 开始本房间推流: 用已设置的视频文件启动播放进程(暂停在 0 秒),
  /// 捕获其窗口发布到本房间, 并向服务端登记本房间推流
  Future<void> startVideoCast(int roomId) async {
    final path = _videoFiles[roomId];
    if (path == null || path.isEmpty) {
      throw StateError('请先为本房间选择视频文件');
    }
    if (!_transitioning.add(roomId)) {
      throw StateError('本房间推流操作进行中, 请稍候');
    }
    try {
      final session = await ensureSession(roomId);
      await session.startVideoCast(
        path,
        onPlayingChanged: (playing, positionMs, durationMs) {
          ApiClient.instance
              .broadcastPlayback(roomId,
                  playing: playing,
                  positionMs: positionMs,
                  durationMs: durationMs)
              .catchError((_) {});
        },
        onClosedExternally: () => stopVideoCast(roomId),
      );
      try {
        await ApiClient.instance
            .startCast(roomId, 'VIDEO', label: fileNameOf(path));
      } catch (_) {
        await session.stopCast();
        rethrow;
      }
      _castStartedAt[roomId] = DateTime.now();
    } finally {
      _transitioning.remove(roomId);
      notifyListeners();
    }
  }

  /// 停止本房间推流: 关闭播放进程(进度归零)并停止捕获轨, 已设置的视频文件保留
  Future<void> stopVideoCast(int roomId, {bool notifyServer = true}) async {
    _transitioning.add(roomId);
    try {
      final session = _sessions[roomId];
      if (session != null) {
        try {
          await session.stopCast();
        } catch (_) {}
      }
      if (notifyServer) {
        try {
          await ApiClient.instance.stopCast(roomId);
        } catch (_) {}
      }
    } finally {
      _transitioning.remove(roomId);
      notifyListeners();
    }
  }

  /// 按总览最新房间状态同步本地推流:
  /// - 房间退出(运行中 -> 关闭/空闲, 或被关闭): 停止推流并初始化状态(文件保留)
  /// - 服务端已停止推流的房间: 本地同步停止播放进程与捕获轨(文件保留)
  Future<void> syncRooms(List<RoomModel> rooms) async {
    final now = DateTime.now();
    for (final room in rooms) {
      if (_transitioning.contains(room.id)) continue;
      final previous = _lastStatus[room.id];
      _lastStatus[room.id] = room.status;

      final exited = previous != null &&
          previous != room.status &&
          (room.closed || (previous == 'RUNNING' && !room.running));
      if (exited) {
        await stopVideoCast(room.id, notifyServer: false);
        continue;
      }

      final session = _sessions[room.id];
      if (session == null || !session.publishing) continue;
      final startedAt = _castStartedAt[room.id];
      if (startedAt != null && now.difference(startedAt) < _syncGrace) {
        continue;
      }
      if (room.closed || !room.casting) {
        await stopVideoCast(room.id, notifyServer: false);
      }
    }
  }

  /// 手机端播放控制指令(经服务端 WS 转发到 PC 端, 只作用于对应房间)
  Future<void> handleRemoteControl(
      int roomId, Map<String, dynamic> payload) async {
    final player = playerOf(roomId);
    if (player == null || !player.started) return;
    switch (payload['action']) {
      case 'playOrPause':
        await player.playOrPause();
        break;
      case 'seek':
        final positionMs = (payload['positionMs'] as num?)?.toInt();
        if (positionMs != null) await player.seek(positionMs);
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
    for (final roomId in _sessions.keys.toList()) {
      try {
        await closeSession(roomId);
      } catch (_) {
        // 单个房间清理失败不中断其余房间清理
      }
    }
    notifyListeners();
  }
}
