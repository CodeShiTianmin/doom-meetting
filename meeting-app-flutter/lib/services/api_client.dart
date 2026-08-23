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

  /// 播放控制: PLAY / PAUSE / SEEK 为共享指令(序号由服务端权威分配)
  Future<Map<String, dynamic>> controlPlayback({
    required String roomCode,
    required String identity,
    required String memberToken,
    required String action,
    double? positionSeconds,
    double? value,
  }) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/playback', data: {
      'identity': identity,
      'memberToken': memberToken,
      'action': action,
      'positionSeconds': positionSeconds,
      'value': value,
    });
    return _unwrap(response);
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

  /// 会中文字聊天/表情: 发送
  Future<void> sendChat({
    required String roomCode,
    required String identity,
    required String memberToken,
    required String content,
  }) async {
    final response = await _dio.post('/api/mobile/rooms/$roomCode/chat', data: {
      'identity': identity,
      'memberToken': memberToken,
      'content': content,
    });
    _unwrap(response);
  }

  /// 聊天历史(最近 100 条)
  Future<List<Map<String, dynamic>>> chatHistory({
    required String roomCode,
    required String identity,
    required String memberToken,
  }) async {
    final response =
        await _dio.get('/api/mobile/rooms/$roomCode/chat', queryParameters: {
      'identity': identity,
      'memberToken': memberToken,
    });
    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw ApiException(
          (body['message'] as String?) ?? '请求失败', body['code'] as int? ?? -1);
    }
    return ((body['data'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 手机端上传真实文件并直接投放到本房间(服务器保存, 会议结束后自动删除);
  /// 已有投放时需 replace=true 确认替换
  Future<Map<String, dynamic>> uploadAndCastFile({
    required String roomCode,
    required String identity,
    required String memberToken,
    String? nickname,
    required String filePath,
    bool replace = false,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      'identity': identity,
      'memberToken': memberToken,
      if (nickname != null) 'nickname': nickname,
      'replace': replace,
    });
    final response = await _dio.post(
      '/api/mobile/rooms/$roomCode/contents/upload',
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
    );
    return _unwrap(response);
  }

  /// 服务器文件下载/打开地址(fileUrl 为服务端下发的带签名 token 的相对地址)
  String fileDownloadUrl(String fileUrl) =>
      fileUrl.startsWith('http') ? fileUrl : '${AppConfig.apiBaseUrl}$fileUrl';

  /// App 版本检查(APK 私发分发)
  Future<Map<String, dynamic>> checkAppVersion(int currentVersionCode) async {
    final response = await _dio.get('/api/app/version',
        queryParameters: {'currentVersionCode': currentVersionCode});
    return _unwrap(response);
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
