/// 房间实时状态(对应后端 GET /api/mobile/rooms/{code}/state)
class RoomState {
  static const Object _unset = Object();

  final String roomCode;
  final String name;
  final String status;
  final bool videoCallEnabled;
  final bool cameraEnabled;
  final bool screenshotAllowed;
  final bool recordingForbidden;
  final int? durationMinutes;
  final String? meetingStartAt;
  final String? meetingEndAt;
  final int? remainingSeconds;
  final bool allMuted;
  final int likeCount;

  /// PC 端当前推流类型: SCREEN/VIDEO/CAMERA, null 表示无推流
  final String? castType;

  /// 推流内容说明(视频文件名/摄像头/屏幕源名称)
  final String? castLabel;

  RoomState({
    required this.roomCode,
    required this.name,
    required this.status,
    required this.videoCallEnabled,
    required this.cameraEnabled,
    required this.screenshotAllowed,
    required this.recordingForbidden,
    this.durationMinutes,
    this.meetingStartAt,
    this.meetingEndAt,
    this.remainingSeconds,
    this.allMuted = false,
    required this.likeCount,
    this.castType,
    this.castLabel,
  });

  bool get running => status == 'RUNNING';
  bool get closed => status == 'CLOSED';
  bool get casting => castType != null;
  bool get camAllowed => videoCallEnabled && cameraEnabled;

  factory RoomState.fromJson(Map<String, dynamic> json) => RoomState(
        roomCode: json['roomCode'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        videoCallEnabled: json['videoCallEnabled'] == true,
        cameraEnabled: json['cameraEnabled'] == true,
        screenshotAllowed: json['screenshotAllowed'] == true,
        recordingForbidden: json['recordingForbidden'] == true,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        meetingStartAt: json['meetingStartAt'] as String?,
        meetingEndAt: json['meetingEndAt'] as String?,
        remainingSeconds: (json['remainingSeconds'] as num?)?.toInt(),
        allMuted: json['allMuted'] == true,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        castType: json['castType'] as String?,
        castLabel: json['castLabel'] as String?,
      );

  /// 可空字段(cast* 等)使用哨兵默认值, 支持显式传 null 清空
  RoomState copyWith({
    String? status,
    bool? videoCallEnabled,
    bool? cameraEnabled,
    Object? remainingSeconds = _unset,
    bool? allMuted,
    int? likeCount,
    Object? castType = _unset,
    Object? castLabel = _unset,
    String? meetingStartAt,
    String? meetingEndAt,
  }) =>
      RoomState(
        roomCode: roomCode,
        name: name,
        status: status ?? this.status,
        videoCallEnabled: videoCallEnabled ?? this.videoCallEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        screenshotAllowed: screenshotAllowed,
        recordingForbidden: recordingForbidden,
        durationMinutes: durationMinutes,
        meetingStartAt: meetingStartAt ?? this.meetingStartAt,
        meetingEndAt: meetingEndAt ?? this.meetingEndAt,
        remainingSeconds: remainingSeconds == _unset
            ? this.remainingSeconds
            : remainingSeconds as int?,
        allMuted: allMuted ?? this.allMuted,
        likeCount: likeCount ?? this.likeCount,
        castType: castType == _unset ? this.castType : castType as String?,
        castLabel: castLabel == _unset ? this.castLabel : castLabel as String?,
      );
}
