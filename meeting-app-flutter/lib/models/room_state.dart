/// 房间实时状态(对应后端 GET /api/mobile/rooms/{code}/state)
class RoomState {
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
  final String playbackState;
  final double playbackPositionSeconds;
  final int likeCount;
  final int? contentId;
  final String? contentName;
  final int? contentDurationSeconds;
  final String? contentType;
  final String? contentFileUrl;
  final String? contentMimeType;

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
    required this.playbackState,
    required this.playbackPositionSeconds,
    required this.likeCount,
    this.contentId,
    this.contentName,
    this.contentDurationSeconds,
    this.contentType,
    this.contentFileUrl,
    this.contentMimeType,
  });

  bool get running => status == 'RUNNING';
  bool get closed => status == 'CLOSED';
  bool get playing => playbackState == 'PLAYING';
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
        playbackState: (json['playbackState'] as String?) ?? 'IDLE',
        playbackPositionSeconds:
            (json['playbackPositionSeconds'] as num?)?.toDouble() ?? 0,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        contentId: (json['contentId'] as num?)?.toInt(),
        contentName: json['contentName'] as String?,
        contentDurationSeconds:
            (json['contentDurationSeconds'] as num?)?.toInt(),
        contentType: json['contentType'] as String?,
        contentFileUrl: json['contentFileUrl'] as String?,
        contentMimeType: json['contentMimeType'] as String?,
      );

  RoomState copyWith({
    String? status,
    bool? videoCallEnabled,
    bool? cameraEnabled,
    int? remainingSeconds,
    String? playbackState,
    double? playbackPositionSeconds,
    int? likeCount,
    int? contentId,
    String? contentName,
    int? contentDurationSeconds,
    String? contentType,
    String? contentFileUrl,
    String? contentMimeType,
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
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        playbackState: playbackState ?? this.playbackState,
        playbackPositionSeconds:
            playbackPositionSeconds ?? this.playbackPositionSeconds,
        likeCount: likeCount ?? this.likeCount,
        contentId: contentId ?? this.contentId,
        contentName: contentName ?? this.contentName,
        contentDurationSeconds:
            contentDurationSeconds ?? this.contentDurationSeconds,
        contentType: contentType ?? this.contentType,
        contentFileUrl: contentFileUrl ?? this.contentFileUrl,
        contentMimeType: contentMimeType ?? this.contentMimeType,
      );
}
