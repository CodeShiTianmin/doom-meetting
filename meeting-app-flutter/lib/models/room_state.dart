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
  final String playbackState;
  final double playbackPositionSeconds;
  final int? playbackSeq;
  final bool screenSharing;
  final bool allMuted;
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
    this.playbackSeq,
    this.screenSharing = false,
    this.allMuted = false,
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
        playbackSeq: (json['playbackSeq'] as num?)?.toInt(),
        screenSharing: json['screenSharing'] == true,
        allMuted: json['allMuted'] == true,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        contentId: (json['contentId'] as num?)?.toInt(),
        contentName: json['contentName'] as String?,
        contentDurationSeconds:
            (json['contentDurationSeconds'] as num?)?.toInt(),
        contentType: json['contentType'] as String?,
        contentFileUrl: json['contentFileUrl'] as String?,
        contentMimeType: json['contentMimeType'] as String?,
      );

  /// 可空字段(content* 等)使用哨兵默认值, 支持显式传 null 清空
  RoomState copyWith({
    String? status,
    bool? videoCallEnabled,
    bool? cameraEnabled,
    Object? remainingSeconds = _unset,
    String? playbackState,
    double? playbackPositionSeconds,
    int? playbackSeq,
    bool? screenSharing,
    bool? allMuted,
    int? likeCount,
    Object? contentId = _unset,
    Object? contentName = _unset,
    Object? contentDurationSeconds = _unset,
    Object? contentType = _unset,
    Object? contentFileUrl = _unset,
    Object? contentMimeType = _unset,
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
        playbackState: playbackState ?? this.playbackState,
        playbackPositionSeconds:
            playbackPositionSeconds ?? this.playbackPositionSeconds,
        playbackSeq: playbackSeq ?? this.playbackSeq,
        screenSharing: screenSharing ?? this.screenSharing,
        allMuted: allMuted ?? this.allMuted,
        likeCount: likeCount ?? this.likeCount,
        contentId: contentId == _unset ? this.contentId : contentId as int?,
        contentName:
            contentName == _unset ? this.contentName : contentName as String?,
        contentDurationSeconds: contentDurationSeconds == _unset
            ? this.contentDurationSeconds
            : contentDurationSeconds as int?,
        contentType:
            contentType == _unset ? this.contentType : contentType as String?,
        contentFileUrl: contentFileUrl == _unset
            ? this.contentFileUrl
            : contentFileUrl as String?,
        contentMimeType: contentMimeType == _unset
            ? this.contentMimeType
            : contentMimeType as String?,
      );
}
