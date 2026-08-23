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
  final String playbackState;
  final double playbackPositionSeconds;
  final int? contentId;
  final String? contentName;
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
    required this.playbackState,
    required this.playbackPositionSeconds,
    this.contentId,
    this.contentName,
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
        playbackState: (json['playbackState'] as String?) ?? 'IDLE',
        playbackPositionSeconds:
            (json['playbackPositionSeconds'] as num?)?.toDouble() ?? 0,
        contentId: (json['contentId'] as num?)?.toInt(),
        contentName: json['contentName'] as String?,
        livekitToken: json['livekitToken'] as String?,
        livekitWsUrl: json['livekitWsUrl'] as String?,
      );
}
