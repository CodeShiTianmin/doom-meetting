import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../config/app_config.dart';

/// 房间实时事件通道: STOMP 订阅 /topic/rooms/{roomCode}
class RoomWsService {
  StompClient? _client;

  void connect(String roomCode, void Function(Map<String, dynamic>) onEvent) {
    disconnect();
    _client = StompClient(
      config: StompConfig(
        url: AppConfig.wsUrl,
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (frame) {
          _client?.subscribe(
            destination: '/topic/rooms/$roomCode',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) return;
              final decoded = jsonDecode(body);
              if (decoded is Map<String, dynamic>) {
                onEvent(decoded);
              }
            },
          );
        },
      ),
    );
    _client?.activate();
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
  }
}
