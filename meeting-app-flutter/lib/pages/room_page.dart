import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_config.dart';
import '../models/join_session.dart';
import '../models/room_state.dart';
import '../services/api_client.dart';
import '../services/recording_guard.dart';
import '../services/ws_service.dart';
import '../widgets/floating_hearts.dart';
import '../widgets/watermark.dart';
import 'join_page.dart';

/// 会议房间页:
/// - PC 隐藏推流为主画面, 两客户互看小窗(受 PC 端开关控制)
/// - 开始播放/暂停/拖拉进度条(两端共享, 带序号防冲突), 明暗/音量本地调节
/// - 会议已进行时长 + 剩余倒计时, 点赞飘心, 心跳保活
/// - 允许截屏, 禁止录制: 检测 -> 遮挡 -> 上报, 全屏水印
class RoomPage extends StatefulWidget {
  final JoinSession session;

  const RoomPage({super.key, required this.session});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final RoomWsService _ws = RoomWsService();
  final RecordingGuard _recordingGuard = RecordingGuard();

  lk.Room? _lkRoom;
  lk.EventsListener<lk.RoomEvent>? _lkListener;
  lk.VideoTrack? _castVideoTrack;
  lk.VideoTrack? _peerVideoTrack;
  lk.LocalVideoTrack? _selfVideoTrack;

  RoomState? _state;
  bool _micOn = true;
  bool _camOn = false;
  bool _frontCamera = true;
  bool _speakerOn = true;
  lk.ConnectionQuality _networkQuality = lk.ConnectionQuality.unknown;
  double _brightness = 0.7;
  double _volume = 0.8;
  double? _draggingPosition;
  int? _elapsedSeconds;
  int? _remainingSeconds;
  bool _recordingBlocked = false;
  String? _closedReason;
  int _commandSeq = DateTime.now().millisecondsSinceEpoch;
  int _heartId = 0;
  final List<HeartItem> _hearts = [];

  Timer? _heartbeatTimer;
  Timer? _stateTimer;
  Timer? _clockTimer;

  JoinSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initLocalControls();
    _refreshState();
    _connectLiveKit();
    _ws.connect(session.roomCode, _onRoomEvent);
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (_) {
      ApiClient.instance
          .heartbeat(session.roomCode, session.identity)
          .catchError((_) {});
    });
    _stateTimer = Timer.periodic(
        AppConfig.stateRefreshInterval, (_) => _refreshState());
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    if (session.recordingForbidden) {
      _recordingGuard.start(_onRecordingDetected);
    }
  }

  Future<void> _initLocalControls() async {
    try {
      final current = await ScreenBrightness().current;
      _brightness = current;
    } catch (_) {}
    try {
      final current = await VolumeController().getVolume();
      _volume = current;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _refreshState() async {
    try {
      final state = await ApiClient.instance.getRoomState(session.roomCode);
      if (!mounted) return;
      setState(() {
        _state = state;
        _remainingSeconds = state.remainingSeconds ?? _remainingSeconds;
      });
      await _enforceFeatureToggles(state);
      if (state.closed && _closedReason == null) {
        _onRoomClosed('会议已结束');
      }
    } catch (_) {}
  }

  /// PC 端关闭视频通话/摄像头后, 已开启的麦克风/摄像头立即关闭
  Future<void> _enforceFeatureToggles(RoomState state) async {
    if (!state.videoCallEnabled && _micOn) {
      await _lkRoom?.localParticipant?.setMicrophoneEnabled(false);
      if (mounted) setState(() => _micOn = false);
    }
    if (!state.camAllowed && _camOn) {
      await _lkRoom?.localParticipant?.setCameraEnabled(false);
      if (mounted) {
        setState(() {
          _camOn = false;
          _selfVideoTrack = null;
        });
      }
    }
  }

  void _tickClock() {
    final state = _state;
    if (state == null || !state.running) return;
    final startAt = state.meetingStartAt;
    setState(() {
      if (startAt != null) {
        final start = DateTime.tryParse(startAt);
        if (start != null) {
          _elapsedSeconds = DateTime.now().difference(start).inSeconds;
        }
      }
      if (_remainingSeconds != null && _remainingSeconds! > 0) {
        _remainingSeconds = _remainingSeconds! - 1;
      }
    });
  }

  // ---------------- LiveKit ----------------

  Future<void> _connectLiveKit() async {
    await [Permission.microphone, Permission.camera].request();
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
    _lkRoom = room;
    _lkListener = room.createListener()
      ..on<lk.TrackSubscribedEvent>((event) => _attachRemoteTrack(
          event.participant, event.track))
      ..on<lk.TrackUnsubscribedEvent>(
          (event) => _detachRemoteTrack(event.participant, event.track))
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        if (event.participant.identity
            .startsWith(AppConfig.castIdentityPrefix)) {
          setState(() => _castVideoTrack = null);
        } else {
          setState(() => _peerVideoTrack = null);
        }
      })
      ..on<lk.ParticipantConnectionQualityUpdatedEvent>((event) {
        // 网络质量指示(本机)
        if (event.participant is lk.LocalParticipant && mounted) {
          setState(() => _networkQuality = event.connectionQuality);
        }
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (_closedReason == null && mounted) {
          setState(() {
            _castVideoTrack = null;
            _peerVideoTrack = null;
          });
        }
      });

    try {
      await room.connect(session.livekitWsUrl, session.livekitToken);
      if (_micOn && session.videoCallEnabled) {
        await room.localParticipant?.setMicrophoneEnabled(true);
      }
    } catch (_) {
      _showToast('媒体服务连接失败, 正在重试…');
    }
  }

  void _attachRemoteTrack(lk.RemoteParticipant participant, lk.Track track) {
    if (track is! lk.VideoTrack) return;
    setState(() {
      if (participant.identity.startsWith(AppConfig.castIdentityPrefix)) {
        _castVideoTrack = track;
      } else {
        _peerVideoTrack = track;
      }
    });
  }

  void _detachRemoteTrack(lk.RemoteParticipant participant, lk.Track track) {
    if (track is! lk.VideoTrack) return;
    setState(() {
      if (participant.identity.startsWith(AppConfig.castIdentityPrefix)) {
        if (_castVideoTrack == track) _castVideoTrack = null;
      } else {
        if (_peerVideoTrack == track) _peerVideoTrack = null;
      }
    });
  }

  Future<void> _toggleMic() async {
    final state = _state;
    if (state == null || !state.videoCallEnabled) {
      _showToast('公司已关闭视频通话功能');
      return;
    }
    final next = !_micOn;
    await _lkRoom?.localParticipant?.setMicrophoneEnabled(next);
    setState(() => _micOn = next);
  }

  Future<void> _toggleCamera() async {
    final state = _state;
    if (state == null || !state.camAllowed) {
      _showToast('公司已关闭摄像头功能');
      return;
    }
    final next = !_camOn;
    final participant = _lkRoom?.localParticipant;
    if (participant == null) return;
    await participant.setCameraEnabled(
      next,
      cameraCaptureOptions: lk.CameraCaptureOptions(
        cameraPosition:
            _frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
      ),
    );
    setState(() {
      _camOn = next;
      _selfVideoTrack = next
          ? participant.videoTrackPublications
              .map((publication) => publication.track)
              .whereType<lk.LocalVideoTrack>()
              .firstOrNull
          : null;
    });
  }

  /// 扬声器/听筒切换
  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await lk.Hardware.instance.setSpeakerphoneOn(next);
    } catch (_) {}
    setState(() => _speakerOn = next);
  }

  Future<void> _switchCamera() async {
    final track = _selfVideoTrack;
    if (track == null) return;
    _frontCamera = !_frontCamera;
    await track.setCameraPosition(
        _frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back);
    setState(() {});
  }

  // ---------------- 房间事件 ----------------

  void _onRoomEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    switch (type) {
      case 'PLAYBACK_CONTROL':
        setState(() {
          _state = _state?.copyWith(
            playbackState: data['playbackState'] as String? ??
                _state?.playbackState,
            playbackPositionSeconds:
                (data['positionSeconds'] as num?)?.toDouble(),
          );
        });
        break;
      case 'SETTINGS_CHANGED':
        _refreshState();
        _showToast('公司更新了房间设置');
        break;
      case 'ROOM_RUNNING':
        _refreshState();
        _showToast('全部客户已就位, 会议开始');
        break;
      case 'CONTENT_CAST':
        _refreshState();
        _showToast('公司已投放: ${data['contentName'] ?? '新内容'}');
        break;
      case 'COUNTDOWN_REMINDER':
        final minutes = data['remainingMinutes'];
        _showToast('会议剩余 $minutes 分钟');
        break;
      case 'LIKE':
        setState(() {
          _state = _state?.copyWith(
              likeCount: (data['likeCount'] as num?)?.toInt());
          _pushHeart();
        });
        break;
      case 'MEMBER_JOINED':
      case 'MEMBER_LEFT':
        _refreshState();
        break;
      case 'ROOM_CLOSED':
        _onRoomClosed((data['reason'] as String?) ?? '会议已结束');
        break;
      default:
        break;
    }
  }

  void _onRoomClosed(String reason) {
    if (_closedReason != null) return;
    setState(() => _closedReason = reason);
    _lkRoom?.disconnect();
  }

  // ---------------- 播放/本地控制 ----------------

  Future<void> _sendPlayback(String action,
      {double? positionSeconds, double? value}) async {
    try {
      final result = await ApiClient.instance.controlPlayback(
        roomCode: session.roomCode,
        identity: session.identity,
        action: action,
        positionSeconds: positionSeconds,
        value: value,
        seq: ++_commandSeq,
      );
      final playbackState = result['playbackState'] as String?;
      if (playbackState != null && mounted) {
        setState(() {
          _state = _state?.copyWith(
            playbackState: playbackState,
            playbackPositionSeconds:
                (result['positionSeconds'] as num?)?.toDouble(),
          );
        });
      }
    } catch (error) {
      _showToast(error.toString());
    }
  }

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    try {
      await ScreenBrightness().setScreenBrightness(value);
    } catch (_) {}
    _sendPlayback('BRIGHTNESS', value: value * 100);
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    try {
      VolumeController().setVolume(value);
    } catch (_) {}
    _sendPlayback('VOLUME', value: value * 100);
  }

  Future<void> _like() async {
    setState(_pushHeart);
    try {
      await ApiClient.instance.sendLike(session.roomCode, session.identity);
    } catch (_) {}
  }

  void _pushHeart() {
    final heart = HeartItem.random(++_heartId);
    _hearts.add(heart);
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() => _hearts.removeWhere((item) => item.id == heart.id));
    });
  }

  // ---------------- 防录制 ----------------

  void _onRecordingDetected(String detail) {
    if (!mounted) return;
    setState(() => _recordingBlocked = true);
    ApiClient.instance
        .reportRecording(session.roomCode, session.identity, detail)
        .catchError((_) {});
  }

  // ---------------- 退出 ----------------

  Future<void> _leave() async {
    try {
      await ApiClient.instance.leaveRoom(session.roomCode, session.identity);
    } catch (_) {}
    await _lkRoom?.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const JoinPage()));
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _stateTimer?.cancel();
    _clockTimer?.cancel();
    _ws.disconnect();
    _recordingGuard.stop();
    try {
      VolumeController().removeListener();
    } catch (_) {}
    _lkListener?.dispose();
    _lkRoom?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 2)));
  }

  String _formatClock(int? seconds) {
    if (seconds == null || seconds < 0) return '--:--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final contentDuration =
        (state.contentDurationSeconds ?? 3600).toDouble();
    final position = _draggingPosition ??
        state.playbackPositionSeconds.clamp(0, contentDuration).toDouble();

    return Scaffold(
      body: Stack(
        children: [
          // 主画面: PC 投放流
          Positioned.fill(
            child: _castVideoTrack != null
                ? lk.VideoTrackRenderer(_castVideoTrack!)
                : _buildWaitingPlaceholder(state),
          ),
          // 对方客户小窗
          if (state.camAllowed && _peerVideoTrack != null)
            Positioned(
              top: 90,
              right: 12,
              width: 108,
              height: 148,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: lk.VideoTrackRenderer(_peerVideoTrack!),
              ),
            ),
          // 本机摄像头预览
          if (_camOn && _selfVideoTrack != null)
            Positioned(
              top: 90,
              right: state.camAllowed && _peerVideoTrack != null ? 128 : 12,
              width: 84,
              height: 116,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: lk.VideoTrackRenderer(
                  _selfVideoTrack!,
                  mirrorMode: _frontCamera
                      ? lk.VideoViewMirrorMode.mirror
                      : lk.VideoViewMirrorMode.off,
                ),
              ),
            ),
          _buildTopBar(state),
          FloatingHearts(hearts: _hearts),
          _buildBottomControls(state, position, contentDuration),
          Positioned.fill(
              child: Watermark(
                  identityText:
                      '${session.roomCode}-${session.identity.substring(session.identity.length > 8 ? session.identity.length - 8 : 0)}')),
          if (_recordingBlocked) _buildRecordingOverlay(),
          if (_closedReason != null) _buildClosedOverlay(),
        ],
      ),
    );
  }

  Widget _buildWaitingPlaceholder(RoomState state) {
    return Container(
      color: const Color(0xFF05071C),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hourglass_bottom,
              size: 44, color: Color(0xFF5B8DEF)),
          const SizedBox(height: 8),
          Text(
            state.contentName != null
                ? '待投放: ${state.contentName}'
                : '等待公司投放内容…',
            style: const TextStyle(color: Colors.white60),
          ),
          if (!state.running)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('全部客户就位后会议开始计时',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(RoomState state) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xD905071C), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor:
                  state.running ? Colors.green.shade700 : Colors.blueGrey,
              label: Text(
                state.running
                    ? '会议进行中'
                    : state.closed
                        ? '已结束'
                        : '等待就位',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${state.name} · ${state.roomCode}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _infoChip(Icons.access_time, _formatClock(_elapsedSeconds)),
            const SizedBox(width: 6),
            _infoChip(Icons.hourglass_bottom, '剩 ${_formatClock(_remainingSeconds)}',
                warning: _remainingSeconds != null && _remainingSeconds! <= 300),
            const SizedBox(width: 6),
            _infoChip(Icons.favorite, '${state.likeCount}'),
            const SizedBox(width: 6),
            _networkChip(),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: warning ? Colors.orange : Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: warning ? Colors.orange : Colors.white70),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontSize: 11,
                  color: warning ? Colors.orange : Colors.white70)),
        ],
      ),
    );
  }

  /// 网络质量指示
  Widget _networkChip() {
    final (color, label) = switch (_networkQuality) {
      lk.ConnectionQuality.excellent => (Colors.green, '网络优'),
      lk.ConnectionQuality.good => (Colors.lightGreen, '网络良'),
      lk.ConnectionQuality.poor => (Colors.orange, '网络差'),
      lk.ConnectionQuality.lost => (Colors.red, '已断开'),
      _ => (Colors.white38, '网络--'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_check, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _buildBottomControls(
      RoomState state, double position, double contentDuration) {
    final canControl = state.running && state.contentId != null;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xEB05071C), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放/暂停 + 进度条(两端同步)
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: canControl
                      ? () => _sendPlayback(
                          state.playing ? 'PAUSE' : 'PLAY',
                          positionSeconds: position)
                      : null,
                  icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    value: position.clamp(0, contentDuration),
                    max: contentDuration,
                    onChanged: canControl
                        ? (value) => setState(() => _draggingPosition = value)
                        : null,
                    onChangeEnd: canControl
                        ? (value) {
                            setState(() => _draggingPosition = null);
                            _sendPlayback('SEEK', positionSeconds: value);
                          }
                        : null,
                  ),
                ),
                Text(_formatClock(position.toInt()),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
            // 明暗 / 音量(本地调节)
            Row(
              children: [
                const Icon(Icons.brightness_6, size: 16, color: Colors.white54),
                Expanded(
                  child: Slider(
                    value: _brightness.clamp(0.05, 1.0),
                    min: 0.05,
                    max: 1.0,
                    onChanged: _setBrightness,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.volume_up, size: 16, color: Colors.white54),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0.0, 1.0),
                    max: 1.0,
                    onChanged: _setVolume,
                  ),
                ),
              ],
            ),
            // 麦克风 / 摄像头 / 切换镜头 / 点赞 / 离开
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: _toggleMic,
                  icon: Icon(_micOn && state.videoCallEnabled
                      ? Icons.mic
                      : Icons.mic_off),
                ),
                IconButton.filledTonal(
                  onPressed: _toggleCamera,
                  icon: Icon(_camOn && state.camAllowed
                      ? Icons.videocam
                      : Icons.videocam_off),
                ),
                IconButton.filledTonal(
                  onPressed: _camOn ? _switchCamera : null,
                  icon: const Icon(Icons.cameraswitch),
                ),
                IconButton.filledTonal(
                  onPressed: _toggleSpeaker,
                  icon: Icon(_speakerOn ? Icons.volume_up : Icons.hearing),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.pink.shade400),
                  onPressed: _like,
                  icon: const Icon(Icons.favorite),
                ),
                IconButton.filled(
                  style:
                      IconButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: _leave,
                  icon: const Icon(Icons.call_end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 检测到录制: 全屏遮挡 + 提示(允许截屏, 禁止录制)
  Widget _buildRecordingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('检测到录屏行为, 会议内容已遮挡',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('本会议允许截屏, 但禁止录制。已上报给会议方。',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => setState(() => _recordingBlocked = false),
              child: const Text('我已停止录制, 恢复画面'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xF205071C),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.meeting_room, size: 56, color: Color(0xFF5B8DEF)),
            const SizedBox(height: 12),
            Text(_closedReason ?? '会议已结束',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _leave, child: const Text('退出房间')),
          ],
        ),
      ),
    );
  }
}
