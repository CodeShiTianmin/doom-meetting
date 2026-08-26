import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// PC 端实时通道:
/// - /topic/admin/dashboard 全局事件(房间运行/红灯预警/点赞/成员进出)
/// - /topic/rooms/{roomCode} 单房间事件(播放控制指令等)
class DesktopWsService {
  StompClient? _client;
  final Map<String, StompUnsubscribe> _roomSubscriptions = {};
  final Map<String, void Function(Map<String, dynamic>)> _roomHandlers = {};
  void Function(Map<String, dynamic>)? _dashboardHandler;
  bool _connected = false;

  void connect(
      {required void Function(Map<String, dynamic>) onDashboardEvent}) {
    _dashboardHandler = onDashboardEvent;
    _client = StompClient(
      config: StompConfig(
        url: AppConfig.wsUrl,
        reconnectDelay: const Duration(seconds: 5),
        stompConnectHeaders: {
          if (ApiClient.instance.token != null)
            'Authorization': 'Bearer ${ApiClient.instance.token}',
        },
        onConnect: (frame) {
          _connected = true;
          _client?.subscribe(
            destination: '/topic/admin/dashboard',
            callback: (frame) => _dispatch(frame.body, _dashboardHandler),
          );
          // 重连后恢复房间订阅
          final rooms = _roomHandlers.keys.toList();
          _roomSubscriptions.clear();
          for (final roomCode in rooms) {
            _subscribeRoom(roomCode);
          }
        },
        onDisconnect: (_) => _connected = false,
      ),
    );
    _client?.activate();
  }

  void subscribeRoom(
      String roomCode, void Function(Map<String, dynamic>) onEvent) {
    _roomHandlers[roomCode] = onEvent;
    if (_connected) _subscribeRoom(roomCode);
  }

  void _subscribeRoom(String roomCode) {
    _roomSubscriptions[roomCode]?.call();
    _roomSubscriptions[roomCode] = _client!.subscribe(
      destination: '/topic/rooms/$roomCode',
      callback: (frame) => _dispatch(frame.body, _roomHandlers[roomCode]),
    );
  }

  void unsubscribeRoom(String roomCode) {
    _roomSubscriptions.remove(roomCode)?.call();
    _roomHandlers.remove(roomCode);
  }

  void _dispatch(String? body, void Function(Map<String, dynamic>)? handler) {
    if (body == null || body.isEmpty || handler == null) return;
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) handler(decoded);
  }

  void disconnect() {
    for (final unsubscribe in _roomSubscriptions.values) {
      unsubscribe();
    }
    _roomSubscriptions.clear();
    _roomHandlers.clear();
    _client?.deactivate();
    _client = null;
    _connected = false;
  }
}
