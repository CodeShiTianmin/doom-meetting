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
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        handler.reject(DioException(
          requestOptions: error.requestOptions,
          response: error.response,
          type: error.type,
          error: ApiException(_describe(error),
              code: error.response?.statusCode ?? -1),
        ));
      },
    ));

  /// 把网络层异常转成可直接展示的提示文案
  static String _describe(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout) {
      return '服务器响应超时, 请检查网络后重试';
    }
    if (type == DioExceptionType.connectionError) {
      return '无法连接服务器, 请检查网络或服务器地址';
    }
    if (type == DioExceptionType.badResponse) {
      return '服务器开小差了 (HTTP ${error.response?.statusCode})';
    }
    if (type == DioExceptionType.cancel) return '请求已取消';
    if (type == DioExceptionType.badCertificate) return '服务器证书无效';
    return '网络请求失败, 请稍后重试';
  }

  /// 校验统一响应包裹 {code,message,data}, 业务失败或响应形态不对时抛出 ApiException
  Map<String, dynamic> _envelope(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      if (response.statusCode == 401) {
        throw ApiException('登录已失效, 请重新登录', code: 401);
      }
      throw ApiException('服务器返回了无法识别的响应 (HTTP ${response.statusCode})',
          code: response.statusCode ?? -1);
    }
    final code = (body['code'] as num?)?.toInt();
    if (code != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败',
          code: code ?? response.statusCode ?? -1);
    }
    return body;
  }

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final data = _envelope(response)['data'];
    if (data is Map<String, dynamic>) return data;
    return {'list': data};
  }

  List<dynamic> _unwrapList(Response<dynamic> response) {
    return (_envelope(response)['data'] as List<dynamic>?) ?? const [];
  }

  void _ensureOk(Response<dynamic> response) {
    _envelope(response);
  }

  bool get loggedIn => _token != null;

  /// 管理端 JWT(WebSocket CONNECT 鉴权用)
  String? get token => _token;

  Future<void> login(String user, String password) async {
    final response = await _dio.post('/api/auth/login',
        data: {'username': user, 'password': password});
    final data = _unwrap(response);
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('登录响应缺少凭证');
    }
    _token = token;
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

  /// 单房推流登记(每个房间独立推流)
  Future<RoomModel> startCast(int id, String type,
      {String? label, bool replace = true}) async {
    final response = await _dio.post('/api/admin/rooms/$id/cast/start',
        data: {'type': type, 'label': label, 'replace': replace});
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 单房停止推流登记
  Future<RoomModel> stopCast(int id) async {
    final response = await _dio.post('/api/admin/rooms/$id/cast/stop');
    return RoomModel.fromJson(_unwrap(response));
  }

  /// 单房播放状态广播(同步到该房间的手机端)
  Future<void> broadcastPlayback(int id,
      {required bool playing, int? positionMs, int? durationMs}) async {
    final response =
        await _dio.post('/api/admin/rooms/$id/cast/playback', data: {
      'playing': playing,
      'positionMs': positionMs,
      'durationMs': durationMs,
    });
    _ensureOk(response);
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

  bool get unauthorized => code == 401;

  @override
  String toString() => message;
}

/// 从任意异常中提取可展示给用户的提示文案
/// (Dio 层异常已在拦截器中包装为 ApiException)
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
