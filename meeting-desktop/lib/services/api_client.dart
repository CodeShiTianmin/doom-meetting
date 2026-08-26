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

  Future<RoomModel> createRoom({
    required String name,
    required int durationMinutes,
    int? maxMembers,
    required bool videoCallEnabled,
    required bool cameraEnabled,
    String? scheduledStartAt,
    bool approvalRequired = false,
  }) async {
    final response = await _dio.post('/api/admin/rooms', data: {
      'name': name,
      'durationMinutes': durationMinutes,
      'maxMembers': maxMembers,
      'videoCallEnabled': videoCallEnabled,
      'cameraEnabled': cameraEnabled,
      'scheduledStartAt': scheduledStartAt,
      'approvalRequired': approvalRequired,
    });
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

  /// 开始推流登记(屏幕/本地视频/摄像头, 均走 LiveKit 实时流);
  /// type: SCREEN / VIDEO / CAMERA, label 为推流源名称
  Future<RoomModel> startCast(int roomId, String type,
      {String? label, bool replace = false}) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/cast/start',
        data: {'type': type, 'label': label, 'replace': replace});
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 停止当前推流登记
  Future<RoomModel> stopCast(int roomId) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/cast/stop');
    return RoomModel.fromJson(_unwrap(response));
  }

  Future<void> closeRoom(int id) async {
    await _dio.post('/api/admin/rooms/$id/close');
  }

  Future<RoomModel> regenerateInvite(int id) async {
    final response = await _dio.post('/api/admin/rooms/$id/invite/regenerate');
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 隐藏推流身份 Token(只发不收, 不出现在成员列表)
  Future<Map<String, dynamic>> getPublisherToken(int roomId) async {
    final response = await _dio.get('/api/admin/rooms/$roomId/publisher-token');
    return _unwrap(response);
  }

  Future<List<dynamic>> listLikes(int roomId) async {
    final response = await _dio.get('/api/admin/rooms/$roomId/likes');
    return _unwrapList(response);
  }

  // ---------- 成员管理 ----------

  Future<void> kickMember(int roomId, String identity) async {
    final response =
        await _dio.post('/api/admin/rooms/$roomId/members/$identity/kick');
    _unwrap(response);
  }

  Future<void> muteMember(int roomId, String identity, bool muted) async {
    final response = await _dio.post(
        '/api/admin/rooms/$roomId/members/$identity/mute',
        queryParameters: {'muted': muted});
    _unwrap(response);
  }

  Future<void> muteAll(int roomId, bool muted) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/members/mute-all',
        queryParameters: {'muted': muted});
    _unwrap(response);
  }

  Future<void> setMemberCamera(
      int roomId, String identity, bool disabled) async {
    final response = await _dio.post(
        '/api/admin/rooms/$roomId/members/$identity/camera',
        queryParameters: {'disabled': disabled});
    _unwrap(response);
  }

  Future<void> approveMember(
      int roomId, String identity, bool approved) async {
    final response = await _dio.post(
        '/api/admin/rooms/$roomId/members/$identity/approve',
        queryParameters: {'approved': approved});
    _unwrap(response);
  }

  /// 会后出席统计报表
  Future<List<dynamic>> attendance(int roomId) async {
    final response = await _dio.get('/api/admin/rooms/$roomId/attendance');
    return _unwrapList(response);
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
