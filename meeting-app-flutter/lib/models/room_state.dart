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

  /// 在线成员数/成员上限(双人匹配: 两人都扫码成功才同时进房)
  final int onlineMemberCount;
  final int maxMembers;

  /// PC 端当前推流类型: SCREEN/VIDEO/CAMERA, null 表示无推流
  final String? castType;

  /// 推流内容说明(视频文件名/摄像头/屏幕源名称)
  final String? castLabel;

  /// 本房间推流当前是否处于播放中(初始暂停)
  final bool castPlaying;

  /// 房间成员名单(含已离线成员, 按入房顺序)
  final List<RoomMemberInfo> members;

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
    this.onlineMemberCount = 0,
    this.maxMembers = 2,
    this.castType,
    this.castLabel,
    this.castPlaying = false,
    this.members = const [],
  });

  bool get running => status == 'RUNNING';
  bool get closed => status == 'CLOSED';
  bool get casting => castType != null;
  bool get camAllowed => videoCallEnabled && cameraEnabled;

  /// 全部成员就位(双人都扫码成功)
  bool get allSeated => onlineMemberCount >= maxMembers;

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
        onlineMemberCount: (json['onlineMemberCount'] as num?)?.toInt() ?? 0,
        maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 2,
        castType: json['castType'] as String?,
        castLabel: json['castLabel'] as String?,
        castPlaying: json['castPlaying'] == true,
        members: ((json['members'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RoomMemberInfo.fromJson)
            .toList(),
      );

  /// 成员退出/离线事件到达时本地先置灰, 不等接口刷新
  RoomState withMemberOffline(String identity) {
    if (!members.any((m) => m.identity == identity && m.online)) return this;
    final updated = members
        .map((m) => m.identity == identity ? m.copyWith(online: false) : m)
        .toList();
    return copyWith(
      members: updated,
      onlineMemberCount: updated.where((m) => m.online).length,
    );
  }

  /// 可空字段(cast* 等)使用哨兵默认值, 支持显式传 null 清空
  RoomState copyWith({
    String? status,
    bool? videoCallEnabled,
    bool? cameraEnabled,
    Object? remainingSeconds = _unset,
    bool? allMuted,
    int? likeCount,
    int? onlineMemberCount,
    int? maxMembers,
    Object? castType = _unset,
    Object? castLabel = _unset,
    bool? castPlaying,
    String? meetingStartAt,
    String? meetingEndAt,
    List<RoomMemberInfo>? members,
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
        onlineMemberCount: onlineMemberCount ?? this.onlineMemberCount,
        maxMembers: maxMembers ?? this.maxMembers,
        castType: castType == _unset ? this.castType : castType as String?,
        castLabel: castLabel == _unset ? this.castLabel : castLabel as String?,
        castPlaying: castPlaying ?? this.castPlaying,
        members: members ?? this.members,
      );
}

/// 房间内成员(人名/座位/在线状态)
class RoomMemberInfo {
  final String identity;
  final String nickname;
  final int? seatNo;
  final bool online;

  const RoomMemberInfo({
    required this.identity,
    required this.nickname,
    this.seatNo,
    required this.online,
  });

  factory RoomMemberInfo.fromJson(Map<String, dynamic> json) => RoomMemberInfo(
        identity: json['identity'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        seatNo: (json['seatNo'] as num?)?.toInt(),
        online: json['online'] == true,
      );

  RoomMemberInfo copyWith({bool? online}) => RoomMemberInfo(
        identity: identity,
        nickname: nickname,
        seatNo: seatNo,
        online: online ?? this.online,
      );
}
