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
    // 业务错误使用 HTTP 4xx + {code,message} 返回, 由 _unwrap 统一解析
    validateStatus: (status) => status != null && status < 500,
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

  Future<void> leaveRoom(
      String roomCode, String identity, String memberToken) async {
    await _dio.post('/api/mobile/rooms/$roomCode/leave',
        data: {'identity': identity, 'memberToken': memberToken});
  }

  Future<void> heartbeat(
      String roomCode, String identity, String memberToken) async {
    await _dio.post('/api/mobile/rooms/$roomCode/heartbeat',
        data: {'identity': identity, 'memberToken': memberToken});
  }

  Future<int> sendLike(
      String roomCode, String identity, String memberToken) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/like',
        data: {'identity': identity, 'memberToken': memberToken});
    return ((_unwrap(response))['likeCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> reportRecording(String roomCode, String identity,
      String memberToken, String detail) async {
    await _dio.post('/api/mobile/rooms/$roomCode/report-recording', data: {
      'identity': identity,
      'memberToken': memberToken,
      'detail': detail
    });
  }

  /// App 版本检查(APK 私发分发)
  Future<Map<String, dynamic>> checkAppVersion(int currentVersionCode) async {
    final response = await _dio.get('/api/app/version',
        queryParameters: {'currentVersionCode': currentVersionCode});
    return _unwrap(response);
  }

  /// 当前成员是否已点赞(重新入会时恢复按钮状态)
  Future<bool> hasLiked(String roomCode, String identity) async {
    final response = await _dio.get('/api/mobile/rooms/$roomCode/liked',
        queryParameters: {'identity': identity});
    return _unwrap(response)['liked'] == true;
  }

  /// 发送文字聊天消息
  Future<void> sendChat(String roomCode, String identity, String memberToken,
      String content) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/chat',
        data: {
          'identity': identity,
          'memberToken': memberToken,
          'content': content
        });
    _unwrap(response);
  }

  /// 房间聊天记录(最多50条, 时间正序)
  Future<List<dynamic>> chatHistory(String roomCode) async {
    final response = await _dio.get('/api/mobile/rooms/$roomCode/chat');
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException(
          (body['message'] as String?) ?? '请求失败', body['code'] as int? ?? -1);
    }
    return (body['data'] as List<dynamic>?) ?? const [];
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
