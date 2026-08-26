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
/// - PC 隐藏推流(屏幕/本地视频/摄像头)为主画面, 两客户互看小窗(受 PC 端开关控制)
/// - 明暗/音量本地调节
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
  int? _elapsedSeconds;
  int? _remainingSeconds;
  bool _recordingBlocked = false;
  String? _closedReason;
  bool _mutedByHost = false;
  bool _cameraDisabledByHost = false;
  int _heartId = 0;
  final List<HeartItem> _hearts = [];
  bool _liked = false;
  bool _focusMode = false;
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();

  Timer? _heartbeatTimer;
  Timer? _stateTimer;
  Timer? _clockTimer;

  JoinSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // 重新入会时恢复主持人管控状态, 避免退出重进后绕过静音/禁摄像头
    _mutedByHost = session.mutedByHost;
    _cameraDisabledByHost = session.cameraDisabledByHost;
    _initLocalControls();
    _refreshState();
    _connectLiveKit();
    _ws.connect(session.roomCode, session.identity, session.memberToken,
        _onRoomEvent);
    _loadChatHistory();
    _restoreLikedState();
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (_) {
      ApiClient.instance
          .heartbeat(session.roomCode, session.identity, session.memberToken)
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

  /// PC 端关闭视频通话/摄像头后, 已开启的麦克风/摄像头立即关闭;
  /// 全员静音仅在开启时同步压制(解除靠 MEMBER_MUTED/ALL_MUTED 事件,
  /// 避免单人静音被周期刷新的 allMuted=false 误解除)
  Future<void> _enforceFeatureToggles(RoomState state) async {
    if (state.allMuted && !_mutedByHost) {
      _mutedByHost = true;
      if (_micOn) {
        await _lkRoom?.localParticipant?.setMicrophoneEnabled(false);
        if (mounted) setState(() => _micOn = false);
      }
    }
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
    int? elapsed = _elapsedSeconds;
    final startAt = state.meetingStartAt;
    if (startAt != null) {
      final start = DateTime.tryParse(startAt);
      if (start != null) {
        elapsed = DateTime.now().difference(start).inSeconds;
      }
    }
    int? remaining = _remainingSeconds;
    if (remaining != null && remaining > 0) {
      remaining = remaining - 1;
    }
    // 仅在数值变化时重建, 避免每秒全页 setState
    if (elapsed != _elapsedSeconds || remaining != _remainingSeconds) {
      setState(() {
        _elapsedSeconds = elapsed;
        _remainingSeconds = remaining;
      });
    }
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
        if (!mounted) return;
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

    final wsUrl = session.livekitWsUrl;
    final lkToken = session.livekitToken;
    if (wsUrl == null || lkToken == null) return;
    try {
      await room.connect(wsUrl, lkToken);
      if (!mounted) {
        await room.disconnect();
        return;
      }
      // 默认扬声器外放(观看推流场景), 与 UI 初始状态保持一致
      try {
        await lk.Hardware.instance.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
      if (_micOn &&
          session.videoCallEnabled &&
          !_mutedByHost &&
          _state?.allMuted != true) {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } else if (mounted && _micOn) {
        // 未实际开启麦克风时同步 UI 状态, 避免图标显示与实际不符
        setState(() => _micOn = false);
      }
    } catch (_) {
      _showToast('媒体服务连接失败, 请退出房间后重新进入');
    }
  }

  void _attachRemoteTrack(lk.RemoteParticipant participant, lk.Track track) {
    if (track is! lk.VideoTrack || !mounted) return;
    setState(() {
      if (participant.identity.startsWith(AppConfig.castIdentityPrefix)) {
        _castVideoTrack = track;
      } else {
        _peerVideoTrack = track;
      }
    });
  }

  void _detachRemoteTrack(lk.RemoteParticipant participant, lk.Track track) {
    if (track is! lk.VideoTrack || !mounted) return;
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
    if ((_mutedByHost || state.allMuted) && !_micOn) {
      _showToast('已被主持人静音, 无法开启麦克风');
      return;
    }
    final next = !_micOn;
    await _lkRoom?.localParticipant?.setMicrophoneEnabled(next);
    if (!mounted) return;
    setState(() => _micOn = next);
  }

  Future<void> _toggleCamera() async {
    final state = _state;
    if (state == null || !state.camAllowed) {
      _showToast('公司已关闭摄像头功能');
      return;
    }
    if (_cameraDisabledByHost && !_camOn) {
      _showToast('已被主持人禁止开启摄像头');
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
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() => _speakerOn = next);
  }

  Future<void> _switchCamera() async {
    final track = _selfVideoTrack;
    if (track == null) return;
    _frontCamera = !_frontCamera;
    await track.setCameraPosition(
        _frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back);
    if (!mounted) return;
    setState(() {});
  }

  // ---------------- 房间事件 ----------------

  void _onRoomEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    switch (type) {
      case 'CAST_STOPPED':
        _refreshState();
        _showToast('公司已停止推流');
        break;
      case 'SETTINGS_CHANGED':
        _refreshState();
        _showToast('公司更新了房间设置');
        break;
      case 'ROOM_RUNNING':
        _refreshState();
        _showToast('公司已开始推流, 会议开始计时');
        break;
      case 'CHAT_MESSAGE':
        setState(() {
          _chatMessages.add(data);
          if (_chatMessages.length > 30) _chatMessages.removeAt(0);
        });
        break;
      case 'CAST_STARTED':
        _refreshState();
        _showToast('公司已开始推流: ${data['castLabel'] ?? ''}');
        break;
      case 'COUNTDOWN_REMINDER':
        final minutes = data['remainingMinutes'];
        _showToast('会议剩余 $minutes 分钟');
        break;
      case 'LIKE':
        setState(() {
          _state = _state?.copyWith(
              likeCount: (data['likeCount'] as num?)?.toInt());
          // 本机点赞已在点击时弹过爱心, 广播回声不重复动画
          if (data['identity'] != session.identity) {
            _pushHeart();
          }
        });
        break;
      case 'MEMBER_KICKED':
        if (data['identity'] == session.identity) {
          _onRoomClosed('您已被主持人移出会议');
        } else {
          _refreshState();
        }
        break;
      case 'MEMBER_MUTED':
        if (data['identity'] == session.identity) {
          final muted = data['muted'] == true;
          _mutedByHost = muted;
          if (muted) {
            _lkRoom?.localParticipant?.setMicrophoneEnabled(false);
            if (mounted) setState(() => _micOn = false);
          }
          _showToast(muted ? '您已被主持人静音' : '主持人已取消对您的静音');
        }
        break;
      case 'ALL_MUTED':
        final muted = data['muted'] == true;
        _mutedByHost = muted;
        if (muted) {
          _lkRoom?.localParticipant?.setMicrophoneEnabled(false);
          if (mounted) setState(() => _micOn = false);
        }
        _showToast(muted ? '主持人已开启全员静音' : '主持人已解除全员静音');
        break;
      case 'MEMBER_CAMERA_DISABLED':
        if (data['identity'] == session.identity) {
          final disabled = data['disabled'] == true;
          _cameraDisabledByHost = disabled;
          if (disabled && _camOn) {
            _lkRoom?.localParticipant?.setCameraEnabled(false);
            if (mounted) {
              setState(() {
                _camOn = false;
                _selfVideoTrack = null;
              });
            }
          }
          _showToast(disabled ? '主持人已禁止您开启摄像头' : '主持人已允许您开启摄像头');
        }
        break;
      case 'ROOM_ACTIVATED':
        _refreshState();
        _showToast('预约会议已开始, 等待全员就位');
        break;
      case 'MEMBER_JOINED':
      case 'MEMBER_LEFT':
        _refreshState();
        break;
      case 'ROOM_CLOSED':
        _onRoomClosed(switch (data['reason']) {
          'TIMEOUT' => '会议时长已到, 会议结束',
          'MANUAL' => '公司已结束会议',
          _ => '会议已结束',
        });
        break;
      default:
        break;
    }
  }

  void _onRoomClosed(String reason) {
    if (_closedReason != null) return;
    _closedReason = reason;
    if (mounted) setState(() {});
    _lkRoom?.disconnect();
  }

  // ---------------- 本地控制 ----------------

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    try {
      await ScreenBrightness().setScreenBrightness(value);
    } catch (_) {}
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    try {
      VolumeController().setVolume(value);
    } catch (_) {}
  }

  Future<void> _restoreLikedState() async {
    try {
      final liked = await ApiClient.instance
          .hasLiked(session.roomCode, session.identity);
      if (mounted && liked) setState(() => _liked = true);
    } catch (_) {}
  }

  /// 点赞(每人限一次)
  Future<void> _like() async {
    if (_liked) {
      _showToast('您已点过赞, 每人只能点赞一次');
      return;
    }
    setState(_pushHeart);
    try {
      await ApiClient.instance
          .sendLike(session.roomCode, session.identity, session.memberToken);
      if (mounted) setState(() => _liked = true);
    } on ApiException catch (error) {
      if (error.code == 409 && mounted) {
        setState(() => _liked = true);
      }
      _showToast(error.message);
    } catch (_) {}
  }

  // ---------------- 文字聊天 ----------------

  Future<void> _loadChatHistory() async {
    try {
      final history =
          await ApiClient.instance.chatHistory(session.roomCode);
      if (!mounted) return;
      setState(() {
        _chatMessages
          ..clear()
          ..addAll(history.whereType<Map<String, dynamic>>());
      });
    } catch (_) {}
  }

  Future<void> _sendChat(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      await ApiClient.instance.sendChat(
          session.roomCode, session.identity, session.memberToken, trimmed);
    } on ApiException catch (error) {
      _showToast('发送失败: ${error.message}');
    } catch (_) {
      _showToast('发送失败, 请重试');
    }
  }

  Future<void> _openChatInput() async {
    _chatController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0F2B),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '发送消息...',
                  counterText: '',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  Navigator.of(sheetContext).pop();
                  _sendChat(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                final text = _chatController.text;
                Navigator.of(sheetContext).pop();
                _sendChat(text);
              },
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
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
        .reportRecording(
            session.roomCode, session.identity, session.memberToken, detail)
        .catchError((_) {});
  }

  // ---------------- 退出 ----------------

  Future<void> _leave() async {
    try {
      await ApiClient.instance.leaveRoom(
          session.roomCode, session.identity, session.memberToken);
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
    _chatController.dispose();
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

    return Scaffold(
      body: Stack(
        children: [
          // 主画面: PC 实时推流 > 等待画面
          Positioned.fill(
            child: _castVideoTrack != null
                ? lk.VideoTrackRenderer(_castVideoTrack!)
                : _buildWaitingPlaceholder(state),
          ),
          // 对方客户小窗
          if (state.camAllowed && _peerVideoTrack != null)
            Positioned(
              top: 130,
              right: 12,
              width: 108,
              height: 148,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: lk.VideoTrackRenderer(_peerVideoTrack!),
                ),
              ),
            ),
          // 本机摄像头预览
          if (_camOn && _selfVideoTrack != null)
            Positioned(
              top: 130,
              right: state.camAllowed && _peerVideoTrack != null ? 128 : 12,
              width: 84,
              height: 116,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
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
            ),
          if (!_focusMode) _buildTopBar(state),
          _buildChatOverlay(),
          FloatingHearts(hearts: _hearts),
          if (!_focusMode) _buildBottomControls(state),
          _buildFocusToggle(),
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
            state.castLabel != null
                ? '推流接入中: ${state.castLabel}'
                : '等待公司推流…',
            style: const TextStyle(color: Colors.white60),
          ),
          if (!state.running)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('公司首次开始推流后会议开始计时',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// 左侧垂直居中: 专注模式开关(隐藏上下菜单, 专注看聊天与投屏)
  Widget _buildFocusToggle() {
    return Positioned(
      left: 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _focusMode ? 0.55 : 0.9,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.45)),
            onPressed: () => setState(() => _focusMode = !_focusMode),
            icon: Icon(
              _focusMode ? Icons.menu : Icons.fullscreen,
              color: Colors.white70,
            ),
            tooltip: _focusMode ? '显示菜单' : '专注模式',
          ),
        ),
      ),
    );
  }

  /// 左下角聊天消息: 最多显示6条, 新消息从底部进入往上排
  Widget _buildChatOverlay() {
    final visible = _chatMessages.length > 6
        ? _chatMessages.sublist(_chatMessages.length - 6)
        : _chatMessages;
    return Positioned(
      left: 56,
      right: 90,
      bottom: _focusMode ? 24 : 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final msg in visible)
            TweenAnimationBuilder<double>(
              key: ValueKey(msg['id'] ?? msg.hashCode),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - value)),
                  child: child,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            '${msg['nickname'] ?? ''}${msg['fromAdmin'] == true ? ' (主持)' : ''}: ',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: msg['fromAdmin'] == true
                                ? Colors.orangeAccent
                                : Colors.lightBlueAccent),
                      ),
                      TextSpan(
                        text: '${msg['content'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
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
        // 两行布局: 第一行为会议状态+房间名, 第二行为时长/倒计时/点赞/网络
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoChip(Icons.access_time, _formatClock(_elapsedSeconds)),
                const SizedBox(width: 6),
                _infoChip(Icons.hourglass_bottom,
                    '剩 ${_formatClock(_remainingSeconds)}',
                    warning: _remainingSeconds != null &&
                        _remainingSeconds! <= 300),
                const SizedBox(width: 6),
                _infoChip(Icons.favorite, '${state.likeCount}'),
                const Spacer(),
                _networkChip(),
              ],
            ),
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

  Widget _buildBottomControls(RoomState state) {
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
                IconButton.filledTonal(
                  onPressed: _openChatInput,
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: _liked
                          ? Colors.grey.shade700
                          : Colors.pink.shade400),
                  onPressed: _like,
                  icon: Icon(_liked ? Icons.favorite : Icons.favorite_border),
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
