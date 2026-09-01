import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/room.dart';

/// PC 端管理接口封装(对应后端 /api/auth + /api/admin/*)
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  String? _token;
  String? username;

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    // 业务错误使用 HTTP 4xx + {code,message} 返回, 由 _unwrap 统一解析
    validateStatus: (status) => status != null && status < 500,
  ))
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (_token != null) {
        options.headers['Authorization'] = 'Bearer $_token';
      }
      handler.next(options);
    }));

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败',
          code: (body['code'] as num?)?.toInt() ?? -1);
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    return {'list': data};
  }

  List<dynamic> _unwrapList(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败',
          code: (body['code'] as num?)?.toInt() ?? -1);
    }
    return (body['data'] as List<dynamic>?) ?? const [];
  }

  bool get loggedIn => _token != null;

  /// 管理端 JWT(WebSocket CONNECT 鉴权用)
  String? get token => _token;

  Future<void> login(String user, String password) async {
    final response = await _dio.post('/api/auth/login',
        data: {'username': user, 'password': password});
    final data = _unwrap(response);
    _token = data['token'] as String;
    username = data['username'] as String?;
  }

  void logout() {
    _token = null;
    username = null;
  }

  // ---------- 房间 ----------

  Future<List<RoomModel>> listRooms() async {
    final response = await _dio.get('/api/admin/rooms');
    return _unwrapList(response)
        .map((item) => RoomModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RoomModel> getRoom(int id) async {
    final response = await _dio.get('/api/admin/rooms/$id');
    return RoomModel.fromJson(_unwrap(response));
  }

  Future<RoomModel> updateSettings(int id,
      {bool? videoCallEnabled,
      bool? cameraEnabled,
      int? durationMinutes,
      int? maxMembers}) async {
    final response = await _dio.put('/api/admin/rooms/$id/settings', data: {
      'videoCallEnabled': videoCallEnabled,
      'cameraEnabled': cameraEnabled,
      'durationMinutes': durationMinutes,
      'maxMembers': maxMembers,
    });
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 统一推流登记: 全部未关闭房间登记同一推流内容
  Future<void> startCastAll(String type, {String? label}) async {
    final response = await _dio.post('/api/admin/rooms/cast/start-all',
        data: {'type': type, 'label': label, 'replace': true});
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException((body['message'] as String?) ?? '推流登记失败',
          code: (body['code'] as num?)?.toInt() ?? -1);
    }
  }

  /// 统一停止推流登记
  Future<void> stopCastAll() async {
    final response = await _dio.post('/api/admin/rooms/cast/stop-all');
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException((body['message'] as String?) ?? '停止推流失败',
          code: (body['code'] as num?)?.toInt() ?? -1);
    }
  }

  /// 统一播放状态广播(同步到全部手机端)
  Future<void> broadcastPlayback(
      {required bool playing, int? positionMs, int? durationMs}) async {
    await _dio.post('/api/admin/rooms/cast/playback', data: {
      'playing': playing,
      'positionMs': positionMs,
      'durationMs': durationMs,
    });
  }

  /// 手动结束会议并重置固定房间(旧凭证失效, 签发新客户码/服务码)
  Future<RoomModel> resetRoom(int id) async {
    final response = await _dio.post('/api/admin/rooms/$id/reset');
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 隐藏推流身份 Token(只发不收, 不出现在成员列表)
  Future<Map<String, dynamic>> getPublisherToken(int roomId) async {
    final response = await _dio.get('/api/admin/rooms/$roomId/publisher-token');
    return _unwrap(response);
  }

}

class ApiException implements Exception {
  final String message;
  final int code;

  ApiException(this.message, {this.code = -1});

  /// 房间已有投放, 需先停止当前投放后再投放
  bool get castConflict => code == 409;

  @override
  String toString() => message;
}
