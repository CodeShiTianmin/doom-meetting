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
      throw ApiException((body['message'] as String?) ?? '请求失败');
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    return {'list': data};
  }

  List<dynamic> _unwrapList(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败');
    }
    return (body['data'] as List<dynamic>?) ?? const [];
  }

  bool get loggedIn => _token != null;

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
  }) async {
    final response = await _dio.post('/api/admin/rooms', data: {
      'name': name,
      'durationMinutes': durationMinutes,
      'maxMembers': maxMembers,
      'videoCallEnabled': videoCallEnabled,
      'cameraEnabled': cameraEnabled,
      'contentId': contentId,
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

  /// 选择内容投给房间(不同时间投不同内容给不同房间)
  Future<RoomModel> castContent(int roomId, int contentId) async {
    final response = await _dio
        .post('/api/admin/rooms/$roomId/cast', data: {'contentId': contentId});
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

  // ---------- 内容库 ----------

  Future<List<ContentModel>> listContents() async {
    final response = await _dio.get('/api/admin/contents');
    return _unwrapList(response)
        .map((item) => ContentModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ContentModel> createContent({
    required String name,
    String? description,
    required String type,
    String? localPath,
    int? durationSeconds,
  }) async {
    final response = await _dio.post('/api/admin/contents', data: {
      'name': name,
      'description': description,
      'type': type,
      'localPath': localPath,
      'durationSeconds': durationSeconds,
      'enabled': true,
    });
    return ContentModel.fromJson(_unwrap(response));
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

  /// 服务器文件下载地址
  String fileDownloadUrl(int contentId) =>
      '${AppConfig.apiBaseUrl}/api/files/$contentId';
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
