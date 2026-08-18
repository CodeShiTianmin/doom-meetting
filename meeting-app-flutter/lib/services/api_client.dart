import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/join_session.dart';
import '../models/room_state.dart';

/// 手机端 REST 接口封装(对应后端 MobileRoomController)
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException(
          (body['message'] as String?) ?? '请求失败', body['code'] as int? ?? -1);
    }
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  Future<JoinSession> joinRoom({
    required String roomCode,
    required String inviteToken,
    required String nickname,
    String? deviceInfo,
  }) async {
    final response = await _dio.post('/api/mobile/rooms/join', data: {
      'roomCode': roomCode,
      'inviteToken': inviteToken,
      'nickname': nickname,
      'deviceInfo': deviceInfo,
    });
    return JoinSession.fromJson(_unwrap(response));
  }

  Future<void> leaveRoom(String roomCode, String identity) async {
    await _dio.post('/api/mobile/rooms/$roomCode/leave',
        data: {'identity': identity});
  }

  Future<void> heartbeat(String roomCode, String identity) async {
    await _dio.post('/api/mobile/rooms/$roomCode/heartbeat',
        data: {'identity': identity});
  }

  /// 播放控制: PLAY / PAUSE / SEEK 为共享指令(带序号防两端冲突)
  Future<Map<String, dynamic>> controlPlayback({
    required String roomCode,
    required String identity,
    required String action,
    double? positionSeconds,
    double? value,
    required int seq,
  }) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/playback', data: {
      'identity': identity,
      'action': action,
      'positionSeconds': positionSeconds,
      'value': value,
      'seq': seq,
    });
    return _unwrap(response);
  }

  Future<int> sendLike(String roomCode, String identity) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/like',
        data: {'identity': identity});
    return ((_unwrap(response))['likeCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> reportRecording(
      String roomCode, String identity, String detail) async {
    await _dio.post('/api/mobile/rooms/$roomCode/report-recording',
        data: {'identity': identity, 'detail': detail});
  }

  Future<RoomState> getRoomState(String roomCode) async {
    final response = await _dio.get('/api/mobile/rooms/$roomCode/state');
    return RoomState.fromJson(_unwrap(response));
  }
}

class ApiException implements Exception {
  final String message;
  final int code;

  ApiException(this.message, this.code);

  @override
  String toString() => message;
}
