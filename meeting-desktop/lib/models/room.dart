/// 房间(对应后端 RoomResponse)
class RoomModel {
  final int id;
  final String roomCode;
  final String name;
  final String status;
  final bool videoCallEnabled;
  final bool cameraEnabled;
  final int? durationMinutes;
  final String? meetingStartAt;
  final String? meetingEndAt;
  final int? remainingSeconds;
  final String? castType;
  final String? castLabel;
  final String? castBy;
  final int likeCount;
  final bool understaffedAlert;
  final int maxMembers;
  final int onlineMemberCount;
  final String? inviteUrl;
  final String? qrContent;
  final String? inviteExpireAt;
  final String? scheduledStartAt;
  final bool approvalRequired;
  final bool allMuted;
  final List<SeatInviteModel> invites;
  final List<MemberModel> members;

  RoomModel({
    required this.id,
    required this.roomCode,
    required this.name,
    required this.status,
    required this.videoCallEnabled,
    required this.cameraEnabled,
    this.durationMinutes,
    this.meetingStartAt,
    this.meetingEndAt,
    this.remainingSeconds,
    this.castType,
    this.castLabel,
    this.castBy,
    required this.likeCount,
    required this.understaffedAlert,
    required this.maxMembers,
    required this.onlineMemberCount,
    this.inviteUrl,
    this.qrContent,
    this.inviteExpireAt,
    this.scheduledStartAt,
    this.approvalRequired = false,
    this.allMuted = false,
    this.invites = const [],
    required this.members,
  });

  bool get running => status == 'RUNNING';
  bool get closed => status == 'CLOSED';
  bool get scheduled => status == 'SCHEDULED';
  bool get casting => castType != null;

  /// 推流内容描述: 视频推流只显示完整文件名, 其它类型显示类型名称
  String? get castDescription {
    if (castType == null) return null;
    final label = castLabel;
    if (label != null && label.isNotEmpty) return label;
    return switch (castType) {
      'SCREEN' => '屏幕共享',
      'CAMERA' => '摄像头推流',
      _ => '推流中',
    };
  }

  factory RoomModel.fromJson(Map<String, dynamic> json) => RoomModel(
        id: (json['id'] as num).toInt(),
        roomCode: json['roomCode'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        videoCallEnabled: json['videoCallEnabled'] == true,
        cameraEnabled: json['cameraEnabled'] == true,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        meetingStartAt: json['meetingStartAt'] as String?,
        meetingEndAt: json['meetingEndAt'] as String?,
        remainingSeconds: (json['remainingSeconds'] as num?)?.toInt(),
        castType: json['castType'] as String?,
        castLabel: json['castLabel'] as String?,
        castBy: json['castBy'] as String?,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        understaffedAlert: json['understaffedAlert'] == true,
        maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 2,
        onlineMemberCount: (json['onlineMemberCount'] as num?)?.toInt() ?? 0,
        inviteUrl: json['inviteUrl'] as String?,
        qrContent: json['qrContent'] as String?,
        inviteExpireAt: json['inviteExpireAt'] as String?,
        scheduledStartAt: json['scheduledStartAt'] as String?,
        approvalRequired: json['approvalRequired'] == true,
        allMuted: json['allMuted'] == true,
        invites: ((json['invites'] as List<dynamic>?) ?? const [])
            .map((item) =>
                SeatInviteModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        members: ((json['members'] as List<dynamic>?) ?? const [])
            .map((item) => MemberModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class MemberModel {
  final int id;
  final String identity;
  final String nickname;
  final bool online;
  final String? joinedAt;
  final int? seatNo;
  final bool muted;
  final bool cameraDisabled;
  final bool kicked;
  final bool approved;

  MemberModel({
    required this.id,
    required this.identity,
    required this.nickname,
    required this.online,
    this.joinedAt,
    this.seatNo,
    this.muted = false,
    this.cameraDisabled = false,
    this.kicked = false,
    this.approved = true,
  });

  factory MemberModel.fromJson(Map<String, dynamic> json) => MemberModel(
        id: (json['id'] as num).toInt(),
        identity: json['identity'] as String,
        nickname: json['nickname'] as String,
        online: json['online'] == true,
        joinedAt: json['joinedAt'] as String?,
        seatNo: (json['seatNo'] as num?)?.toInt(),
        muted: json['muted'] == true,
        cameraDisabled: json['cameraDisabled'] == true,
        kicked: json['kicked'] == true,
        approved: json['approved'] != false,
      );
}

/// 座位邀请码(每个座位独立二维码)
class SeatInviteModel {
  final int? seatNo;
  final String token;
  final String? inviteUrl;
  final String? expireAt;
  final bool used;
  final bool revoked;

  SeatInviteModel({
    this.seatNo,
    required this.token,
    this.inviteUrl,
    this.expireAt,
    this.used = false,
    this.revoked = false,
  });

  factory SeatInviteModel.fromJson(Map<String, dynamic> json) =>
      SeatInviteModel(
        seatNo: (json['seatNo'] as num?)?.toInt(),
        token: json['token'] as String,
        inviteUrl: json['inviteUrl'] as String?,
        expireAt: json['expireAt'] as String?,
        used: json['used'] == true,
        revoked: json['revoked'] == true,
      );
}
