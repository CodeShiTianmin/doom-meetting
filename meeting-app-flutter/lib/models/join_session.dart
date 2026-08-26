/// 入会成功后的会话信息(对应后端 JoinRoomResponse)
class JoinSession {
  final int memberId;
  final String identity;
  final String memberToken;
  final int? seatNo;
  final bool pendingApproval;
  final String roomCode;
  final String roomName;
  final String roomStatus;
  final bool videoCallEnabled;
  final bool cameraEnabled;
  final bool screenshotAllowed;
  final bool recordingForbidden;
  final int? durationMinutes;
  final String? meetingStartAt;
  final String? meetingEndAt;
  final String? castType;
  final String? castLabel;

  /// 重新入会时恢复主持人管控状态(单人静音含全员静音/禁摄像头)
  final bool mutedByHost;
  final bool cameraDisabledByHost;
  final String? livekitToken;
  final String? livekitWsUrl;

  JoinSession({
    required this.memberId,
    required this.identity,
    required this.memberToken,
    this.seatNo,
    this.pendingApproval = false,
    required this.roomCode,
    required this.roomName,
    required this.roomStatus,
    required this.videoCallEnabled,
    required this.cameraEnabled,
    required this.screenshotAllowed,
    required this.recordingForbidden,
    this.durationMinutes,
    this.meetingStartAt,
    this.meetingEndAt,
    this.castType,
    this.castLabel,
    this.mutedByHost = false,
    this.cameraDisabledByHost = false,
    this.livekitToken,
    this.livekitWsUrl,
  });

  factory JoinSession.fromJson(Map<String, dynamic> json) => JoinSession(
        memberId: (json['memberId'] as num).toInt(),
        identity: json['identity'] as String,
        memberToken: (json['memberToken'] as String?) ?? '',
        seatNo: (json['seatNo'] as num?)?.toInt(),
        pendingApproval: json['pendingApproval'] == true,
        roomCode: json['roomCode'] as String,
        roomName: json['roomName'] as String,
        roomStatus: json['roomStatus'] as String,
        videoCallEnabled: json['videoCallEnabled'] == true,
        cameraEnabled: json['cameraEnabled'] == true,
        screenshotAllowed: json['screenshotAllowed'] == true,
        recordingForbidden: json['recordingForbidden'] == true,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        meetingStartAt: json['meetingStartAt'] as String?,
        meetingEndAt: json['meetingEndAt'] as String?,
        castType: json['castType'] as String?,
        castLabel: json['castLabel'] as String?,
        mutedByHost: json['muted'] == true,
        cameraDisabledByHost: json['cameraDisabled'] == true,
        livekitToken: json['livekitToken'] as String?,
        livekitWsUrl: json['livekitWsUrl'] as String?,
      );
}
