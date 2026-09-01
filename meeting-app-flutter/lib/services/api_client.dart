import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/join_session.dart';
import '../models/room_state.dart';

/// 手机端 REST 接口封装(对应后端 MobileRoomController)
class ApiClient {
  ApiClient._() {
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        handler.reject(DioException(
          requestOptions: error.requestOptions,
          response: error.response,
          type: error.type,
          error: ApiException(_describeNetworkError(error), -1),
        ));
      },
    ));
  }

  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    // 业务错误使用 HTTP 4xx + {code,message} 返回, 由 _envelope 统一解析
    validateStatus: (status) => status != null && status < 500,
  ));

  static String _describeNetworkError(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout) {
      return '网络超时, 请检查网络后重试';
    }
    if (type == DioExceptionType.connectionError) {
      return '无法连接服务器, 请检查网络';
    }
    if (type == DioExceptionType.badResponse) {
      return '服务器异常 (HTTP ${error.response?.statusCode ?? '?'})';
    }
    if (type == DioExceptionType.cancel) return '请求已取消';
    if (type == DioExceptionType.badCertificate) return '服务器证书校验失败';
    return '网络请求失败, 请稍后重试';
  }

  Map<String, dynamic> _envelope(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException(
          '服务器返回了无法识别的响应 (HTTP ${response.statusCode})',
          response.statusCode ?? -1);
    }
    final code = (body['code'] as num?)?.toInt();
    if (code != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败',
          code ?? response.statusCode ?? -1);
    }
    return body;
  }

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final data = _envelope(response)['data'];
    return data is Map<String, dynamic> ? data : const {};
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
    final response = await _dio.post('/api/mobile/rooms/$roomCode/heartbeat',
        data: {'identity': identity, 'memberToken': memberToken});
    _envelope(response);
  }

  Future<int> sendLike(
      String roomCode, String identity, String memberToken) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/like',
        data: {'identity': identity, 'memberToken': memberToken});
    return ((_unwrap(response))['likeCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> sendChat(String roomCode, String identity, String memberToken,
      String content) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/chat', data: {
      'identity': identity,
      'memberToken': memberToken,
      'content': content,
    });
    _envelope(response);
  }

  Future<List<Map<String, dynamic>>> fetchChat(String roomCode) async {
    final response = await _dio.get('/api/mobile/rooms/$roomCode/chat');
    final data = _envelope(response)['data'];
    if (data is! List<dynamic>) return const [];
    return data.whereType<Map<String, dynamic>>().toList();
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

  /// 统一推流播放控制: 播放/暂停/进度(经服务端转发 PC 端执行)
  /// action: playOrPause / seek
  Future<void> castControl(String roomCode, String identity,
      String memberToken, String action, {int? positionMs}) async {
    final response =
        await _dio.post('/api/mobile/rooms/$roomCode/cast/control', data: {
      'identity': identity,
      'memberToken': memberToken,
      'action': action,
      'positionMs': positionMs,
    });
    _envelope(response);
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

/// 把任意异常转换为可直接展示给用户的文案
String describeError(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) {
    final wrapped = error.error;
    if (wrapped is ApiException) return wrapped.message;
    return error.message ?? '网络请求失败';
  }
  if (error is StateError) return error.message;
  return error.toString();
}
