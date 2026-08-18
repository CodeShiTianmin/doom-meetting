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
  final int? contentId;
  final String? contentName;
  final String playbackState;
  final double playbackPositionSeconds;
  final int likeCount;
  final bool understaffedAlert;
  final int maxMembers;
  final int onlineMemberCount;
  final String? inviteUrl;
  final String? qrContent;
  final String? inviteExpireAt;
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
    this.contentId,
    this.contentName,
    required this.playbackState,
    required this.playbackPositionSeconds,
    required this.likeCount,
    required this.understaffedAlert,
    required this.maxMembers,
    required this.onlineMemberCount,
    this.inviteUrl,
    this.qrContent,
    this.inviteExpireAt,
    required this.members,
  });

  bool get running => status == 'RUNNING';
  bool get closed => status == 'CLOSED';

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
        contentId: (json['contentId'] as num?)?.toInt(),
        contentName: json['contentName'] as String?,
        playbackState: (json['playbackState'] as String?) ?? 'IDLE',
        playbackPositionSeconds:
            (json['playbackPositionSeconds'] as num?)?.toDouble() ?? 0,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        understaffedAlert: json['understaffedAlert'] == true,
        maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 2,
        onlineMemberCount: (json['onlineMemberCount'] as num?)?.toInt() ?? 0,
        inviteUrl: json['inviteUrl'] as String?,
        qrContent: json['qrContent'] as String?,
        inviteExpireAt: json['inviteExpireAt'] as String?,
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

  MemberModel({
    required this.id,
    required this.identity,
    required this.nickname,
    required this.online,
    this.joinedAt,
  });

  factory MemberModel.fromJson(Map<String, dynamic> json) => MemberModel(
        id: (json['id'] as num).toInt(),
        identity: json['identity'] as String,
        nickname: json['nickname'] as String,
        online: json['online'] == true,
        joinedAt: json['joinedAt'] as String?,
      );
}

/// 投放内容(对应后端 ContentResponse)
class ContentModel {
  final int id;
  final String name;
  final String? description;
  final String type;
  final String? localPath;
  final int? durationSeconds;
  final bool enabled;

  ContentModel({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.localPath,
    this.durationSeconds,
    required this.enabled,
  });

  factory ContentModel.fromJson(Map<String, dynamic> json) => ContentModel(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        type: (json['type'] as String?) ?? 'LOCAL_FILE',
        localPath: json['localPath'] as String?,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        enabled: json['enabled'] == true,
      );
}
