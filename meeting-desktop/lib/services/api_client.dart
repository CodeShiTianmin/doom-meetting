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
    int? contentId,
    String? scheduledStartAt,
    bool approvalRequired = false,
  }) async {
    final response = await _dio.post('/api/admin/rooms', data: {
      'name': name,
      'durationMinutes': durationMinutes,
      'maxMembers': maxMembers,
      'videoCallEnabled': videoCallEnabled,
      'cameraEnabled': cameraEnabled,
      'contentId': contentId,
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

  /// 选择内容投给房间(不同时间投不同内容给不同房间); 已有投放时需 replace=true 确认替换
  Future<RoomModel> castContent(int roomId, int contentId,
      {bool replace = false}) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/cast',
        data: {'contentId': contentId, 'replace': replace});
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 停止当前投放(清除房间当前内容并重置播放状态)
  Future<RoomModel> stopCastContent(int roomId) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/cast/stop');
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 屏幕/窗口共享开始登记(服务端状态, 跨端冲突检查可感知)
  Future<RoomModel> startScreenShare(int roomId, {bool replace = false}) async {
    final response = await _dio.post(
        '/api/admin/rooms/$roomId/screen-share/start',
        queryParameters: {'replace': replace});
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 屏幕/窗口共享停止登记
  Future<RoomModel> stopScreenShare(int roomId) async {
    final response =
        await _dio.post('/api/admin/rooms/$roomId/screen-share/stop');
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 删除内容(上传成功但投放失败时清理孤儿文件)
  Future<void> deleteContent(int contentId) async {
    await _dio.delete('/api/admin/contents/$contentId');
  }

  /// PC 端播放控制: PLAY/PAUSE/SEEK/BRIGHTNESS/VOLUME, 实时下发到房间内全部手机端
  Future<Map<String, dynamic>> controlPlayback(int roomId, String action,
      {double? positionSeconds, double? value}) async {
    final response = await _dio.post('/api/admin/rooms/$roomId/playback', data: {
      'action': action,
      'positionSeconds': positionSeconds,
      'value': value,
    });
    return _unwrap(response);
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

  // ---------- 聊天 ----------

  Future<void> sendChat(int roomId, String content) async {
    final response = await _dio
        .post('/api/admin/rooms/$roomId/chat', data: {'content': content});
    _unwrap(response);
  }

  Future<List<dynamic>> chatHistory(int roomId) async {
    final response = await _dio.get('/api/admin/rooms/$roomId/chat');
    return _unwrapList(response);
  }

  // ---------- 内容库 ----------

  Future<List<ContentModel>> listContents() async {
    final response = await _dio.get('/api/admin/contents');
    return _unwrapList(response)
        .map((item) => ContentModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 真实文件上传到服务器存储(所有类型), 关联房间后会议结束自动删除
  Future<ContentModel> uploadContentFile(String filePath,
      {int? roomId}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (roomId != null) 'roomId': roomId,
    });
    final response = await _dio.post(
      '/api/admin/contents/upload',
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
    );
    return ContentModel.fromJson(_unwrap(response));
  }

  /// 服务器文件下载地址(fileUrl 为服务端下发的带签名 token 的相对地址)
  String fileDownloadUrl(String fileUrl) =>
      fileUrl.startsWith('http') ? fileUrl : '${AppConfig.apiBaseUrl}$fileUrl';
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
