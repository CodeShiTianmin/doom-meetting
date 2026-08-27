import 'api_client.dart';
import 'cast_session.dart';

/// 多房并发投放管理: 维护"房间 -> 独立投放会话"绑定列表.
/// 不同时间为不同房间选择不同内容, 各会话独立连接/独立播放器, 互不干扰.
class CastManager {
  CastManager._();

  static final CastManager instance = CastManager._();

  final Map<int, CastSession> _sessions = {};

  CastSession? sessionOf(int roomId) => _sessions[roomId];

  Iterable<CastSession> get sessions => _sessions.values;

  /// 获取或创建房间投放会话(懒连接: 首次使用时申请隐藏推流 Token 并连接)
  Future<CastSession> ensureSession(int roomId) async {
    final existing = _sessions[roomId];
    if (existing != null && existing.connected) return existing;

    final tokenInfo = await ApiClient.instance.getPublisherToken(roomId);
    final session = existing ??
        CastSession(roomId: roomId, roomCode: tokenInfo['roomCode'] as String);
    // 播放窗口被手动关闭时同步服务端推流登记
    session.onPlayerClosedExternally ??= () async {
      try {
        await ApiClient.instance.stopCast(roomId);
      } catch (_) {}
    };
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

  Future<void> closeSession(int roomId) async {
    final session = _sessions.remove(roomId);
    await session?.disconnect();
    session?.dispose();
  }

  Future<void> closeAll() async {
    for (final roomId in _sessions.keys.toList()) {
      try {
        await closeSession(roomId);
      } catch (_) {
        // 单个房间清理失败不中断其余房间清理
      }
    }
  }
}
