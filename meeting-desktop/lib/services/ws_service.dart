import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// 连接状态(已连接 / 断开重连中), 供页面展示实时通道状态
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  void connect(
      {required void Function(Map<String, dynamic>) onDashboardEvent}) {
    disconnect();
    _dashboardHandler = onDashboardEvent;
    _client = StompClient(
      config: StompConfig(
        url: AppConfig.wsUrl,
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
        stompConnectHeaders: {
          if (ApiClient.instance.token != null)
            'Authorization': 'Bearer ${ApiClient.instance.token}',
        },
        onConnect: (frame) {
          _connected = true;
          connected.value = true;
          _client?.subscribe(
            destination: '/topic/admin/dashboard',
            callback: (frame) => _dispatch(frame.body, _dashboardHandler),
          );
          // 重连后恢复房间订阅(旧订阅句柄随连接已失效)
          final rooms = _roomHandlers.keys.toList();
          _roomSubscriptions.clear();
          for (final roomCode in rooms) {
            _subscribeRoom(roomCode);
          }
        },
        onDisconnect: (_) => _markDisconnected(),
        onWebSocketDone: _markDisconnected,
        onWebSocketError: (_) => _markDisconnected(),
        onStompError: (_) => _markDisconnected(),
      ),
    );
    _client?.activate();
  }

  void _markDisconnected() {
    _connected = false;
    connected.value = false;
    _roomSubscriptions.clear();
  }

  void subscribeRoom(
      String roomCode, void Function(Map<String, dynamic>) onEvent) {
    _roomHandlers[roomCode] = onEvent;
    if (_connected) _subscribeRoom(roomCode);
  }

  void _subscribeRoom(String roomCode) {
    final client = _client;
    if (client == null || !_connected) return;
    _roomSubscriptions[roomCode]?.call();
    _roomSubscriptions[roomCode] = client.subscribe(
      destination: '/topic/rooms/$roomCode',
      callback: (frame) => _dispatch(frame.body, _roomHandlers[roomCode]),
    );
  }

  void unsubscribeRoom(String roomCode) {
    final unsubscribe = _roomSubscriptions.remove(roomCode);
    _roomHandlers.remove(roomCode);
    if (unsubscribe == null || !_connected) return;
    try {
      unsubscribe();
    } catch (_) {}
  }

  void _dispatch(String? body, void Function(Map<String, dynamic>)? handler) {
    if (body == null || body.isEmpty || handler == null) return;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return;
    }
    if (decoded is Map<String, dynamic>) handler(decoded);
  }

  void disconnect() {
    if (_connected) {
      for (final unsubscribe in _roomSubscriptions.values) {
        try {
          unsubscribe();
        } catch (_) {}
      }
    }
    _roomSubscriptions.clear();
    _roomHandlers.clear();
    _client?.deactivate();
    _client = null;
    _connected = false;
    connected.value = false;
  }

  void dispose() {
    disconnect();
    connected.dispose();
  }
}
