import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../config/app_config.dart';

/// 房间实时事件通道: STOMP 订阅 /topic/rooms/{roomCode}
class RoomWsService {
  StompClient? _client;

  /// 连接状态(供页面显示"实时同步中/重连中")
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  void connect(String roomCode, String identity, String memberToken,
      void Function(Map<String, dynamic>) onEvent) {
    disconnect();
    final client = StompClient(
      config: StompConfig(
        url: AppConfig.wsUrl,
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
        stompConnectHeaders: {
          'roomCode': roomCode,
          'identity': identity,
          'memberToken': memberToken,
        },
        onConnect: (frame) {
          connected.value = true;
          _client?.subscribe(
            destination: '/topic/rooms/$roomCode',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) return;
              try {
                final decoded = jsonDecode(body);
                if (decoded is Map<String, dynamic>) onEvent(decoded);
              } on FormatException {
                // 忽略非法 JSON, 不让单条脏数据中断事件流
              }
            },
          );
        },
        onDisconnect: (_) => connected.value = false,
        onWebSocketDone: () => connected.value = false,
        onWebSocketError: (_) => connected.value = false,
        onStompError: (_) => connected.value = false,
      ),
    );
    _client = client;
    client.activate();
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
    connected.value = false;
  }

  void dispose() {
    disconnect();
    connected.dispose();
  }
}
