import 'dart:async';
import 'dart:io';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_pip/livekit_pip.dart';
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
import '../widgets/chat_overlay.dart';
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

  /// 离开 APP 时自动进入画中画悬浮窗(Android)
  Floating? _floating;

  /// 离开 APP 时推流画面画中画(iOS, 无推流画面时系统不显示悬浮窗)
  LiveKitPip? _iosPip;

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
  bool _uiHidden = false;
  int _chatId = 0;
  final List<ChatMessageItem> _chatMessages = [];
  bool _chatInputVisible = false;
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

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
    _loadChatHistory();
    _connectLiveKit();
    _ws.connect(
        session.roomCode, session.identity, session.memberToken, _onRoomEvent);
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (_) {
      ApiClient.instance
          .heartbeat(session.roomCode, session.identity, session.memberToken)
          .catchError((_) {});
    });
    _stateTimer =
        Timer.periodic(AppConfig.stateRefreshInterval, (_) => _refreshState());
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    if (session.recordingForbidden) {
      _recordingGuard.start(_onRecordingDetected);
    }
    _initPip();
  }

  /// 返回桌面/切到其他应用时自动进入画中画悬浮窗,
  /// 点击悬浮窗(展开按钮)回到 APP
  Future<void> _initPip() async {
    if (!Platform.isAndroid) return;
    final floating = Floating();
    try {
      if (!await floating.isPipAvailable) return;
    } catch (_) {
      return;
    }
    _floating = floating;
    if (mounted) setState(() {});
    try {
      // Android 12+ (API 31): 系统自动在返回桌面/切后台时进入画中画
      await floating
          .enable(const OnLeavePiP(aspectRatio: Rational.landscape()));
    } catch (_) {
      // Android 8~11 不支持 OnLeavePiP(setAutoEnterEnabled),
      // 由原生 onUserLeaveHint 在返回桌面时手动进入画中画
    }
    try {
      await _pipChannel.invokeMethod('setAutoPipOnLeave', true);
    } catch (_) {}
  }

  static const MethodChannel _pipChannel =
      MethodChannel('com.doommeeting/pip');

  /// 系统返回键: 进入画中画悬浮窗而非直接退出
  void _onBackPressed() {
    final floating = _floating;
    if (floating != null) {
      floating
          .enable(const ImmediatePiP(aspectRatio: Rational.landscape()))
          .catchError((_) => PiPStatus.unavailable);
      return;
    }
    SystemNavigator.pop();
  }

  Future<void> _initIosPip(lk.Room room) async {
    if (!Platform.isIOS) return;
    final pip = LiveKitPip();
    try {
      await pip.initialize(
        room: room,
        config: LiveKitPipConfiguration(
          android: AndroidPipConfiguration(
            pipWidgetBuilder: (context, room) => const SizedBox.shrink(),
            autoEnterOnBackground: false,
          ),
          ios: const IosPipConfiguration(
            includeLocalParticipantVideo: false,
          ),
        ),
      );
      if (!mounted) {
        unawaited(pip.dispose());
        return;
      }
      setState(() => _iosPip = pip);
    } catch (_) {
      // 设备/系统版本不支持画中画时忽略
      unawaited(pip.dispose());
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
      ..on<lk.TrackSubscribedEvent>(
          (event) => _attachRemoteTrack(event.participant, event.track))
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
      unawaited(_initIosPip(room));
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
      case 'CHAT':
        setState(() {
          _chatMessages.add(ChatMessageItem(
            id: ++_chatId,
            sender: (data['sender'] as String?) ?? '匿名',
            content: (data['content'] as String?) ?? '',
            fromAdmin: data['fromAdmin'] == true,
          ));
          if (_chatMessages.length > 50) {
            _chatMessages.removeRange(0, _chatMessages.length - 50);
          }
        });
        break;
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
        _showToast('全部客户已就位, 会议开始');
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
          _state =
              _state?.copyWith(likeCount: (data['likeCount'] as num?)?.toInt());
          // 本机点赞已在点击时弹过爱心, 广播回声不重复动画
          if (data['identity'] != session.identity) {
            _pushHeart();
          } else {
            _liked = true;
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

  Future<void> _like() async {
    if (_liked) {
      _showToast('每人仅可点赞一次');
      return;
    }
    setState(() {
      _liked = true;
      _pushHeart();
    });
    try {
      await ApiClient.instance
          .sendLike(session.roomCode, session.identity, session.memberToken);
    } on ApiException catch (e) {
      if (e.code != 409) {
        if (mounted) setState(() => _liked = false);
      }
      _showToast(e.message);
    } catch (_) {
      if (mounted) setState(() => _liked = false);
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final records = await ApiClient.instance.fetchChat(session.roomCode);
      if (!mounted) return;
      setState(() {
        _chatMessages
          ..clear()
          ..addAll(records.map((item) => ChatMessageItem(
                id: ++_chatId,
                sender: (item['sender'] as String?) ?? '匿名',
                content: (item['content'] as String?) ?? '',
                fromAdmin: item['fromAdmin'] == true,
              )));
      });
    } catch (_) {}
  }

  Future<void> _sendChat() async {
    final content = _chatController.text.trim();
    if (content.isEmpty) return;
    _chatController.clear();
    try {
      await ApiClient.instance.sendChat(
          session.roomCode, session.identity, session.memberToken, content);
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('消息发送失败');
    }
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
      await ApiClient.instance
          .leaveRoom(session.roomCode, session.identity, session.memberToken);
    } catch (_) {}
    await _lkRoom?.disconnect();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const JoinPage()));
  }

  @override
  void dispose() {
    try {
      _floating?.cancelOnLeavePiP();
    } catch (_) {}
    if (Platform.isAndroid) {
      _pipChannel.invokeMethod('setAutoPipOnLeave', false).catchError((_) {});
    }
    _iosPip?.dispose();
    _heartbeatTimer?.cancel();
    _stateTimer?.cancel();
    _clockTimer?.cancel();
    _ws.disconnect();
    _recordingGuard.stop();
    try {
      VolumeController().removeListener();
    } catch (_) {}
    _chatController.dispose();
    _chatFocus.dispose();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_floating != null) {
      return PiPSwitcher(
        childWhenEnabled: _buildPipView(state),
        childWhenDisabled: _wrapBackToPip(_buildFullView(state)),
      );
    }
    if (Platform.isAndroid) return _wrapBackToPip(_buildFullView(state));
    return _buildFullView(state);
  }

  /// 拦截系统返回键: 返回主界面时进入画中画悬浮窗, 而非直接退出 APP
  Widget _wrapBackToPip(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBackPressed();
      },
      child: child,
    );
  }

  /// 画中画悬浮窗内容: 有推流画面则播放推流, 否则展示会议号与状态
  Widget _buildPipView(RoomState state) {
    final castTrack = _castVideoTrack;
    return Scaffold(
      backgroundColor: Colors.black,
      body: castTrack != null
          ? lk.VideoTrackRenderer(castTrack)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cast_connected,
                      size: 26, color: Colors.white38),
                  const SizedBox(height: 6),
                  Text(session.roomCode,
                      style: const TextStyle(
                          fontSize: 20,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      _closedReason ??
                          (state.running
                              ? '会议进行中 · 暂无推流'
                              : '等待全员就位'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
    );
  }

  Widget _buildFullView(RoomState state) {
    final lkRoom = _lkRoom;
    return Scaffold(
      body: Stack(
        children: [
          // iOS 画中画源视图(透明, 必须铺满屏幕才能触发 PiP), Android 为空占位
          if (_iosPip != null && lkRoom != null)
            Positioned.fill(child: LiveKitPipView(room: lkRoom)),
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
          // 上下菜单可隐藏, 专注观看投屏与聊天
          _buildTopBar(state),
          FloatingHearts(hearts: _hearts),
          // 左下角聊天气泡(最多 6 条, 新消息从下往上滑入)
          Positioned(
            left: 10,
            bottom: _uiHidden ? 28 : (_chatInputVisible ? 210 : 160),
            width: MediaQuery.of(context).size.width * 0.68,
            child: ChatOverlay(messages: _chatMessages),
          ),
          if (!_uiHidden && _chatInputVisible) _buildChatInput(),
          _buildBottomControls(state),
          // 左侧垂直居中: 隐藏/显示上下菜单按钮
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Material(
                color: Colors.black.withValues(alpha: 0.4),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() {
                    _uiHidden = !_uiHidden;
                    if (_uiHidden) {
                      _chatInputVisible = false;
                      _chatFocus.unfocus();
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _uiHidden
                          ? Icons.keyboard_arrow_right
                          : Icons.keyboard_arrow_left,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
            state.castLabel != null ? '推流接入中: ${state.castLabel}' : '等待公司推流…',
            style: const TextStyle(color: Colors.white60),
          ),
          if (state.meetingStartAt == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('公司首次推流后会议开始计时',
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
      child: AnimatedSlide(
        offset: _uiHidden ? const Offset(0, -1) : Offset.zero,
        duration: const Duration(milliseconds: 220),
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
      child: AnimatedSlide(
        offset: _uiHidden ? const Offset(0, 1) : Offset.zero,
        duration: const Duration(milliseconds: 220),
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
                  const Icon(Icons.brightness_6,
                      size: 16, color: Colors.white54),
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
                    onPressed: () {
                      setState(() {
                        _chatInputVisible = !_chatInputVisible;
                      });
                      if (_chatInputVisible) {
                        _chatFocus.requestFocus();
                      }
                    },
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
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade700),
                    onPressed: _leave,
                    icon: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部控制栏上方的聊天输入栏
  Widget _buildChatInput() {
    return Positioned(
      left: 10,
      right: 10,
      bottom: 160,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocus,
                maxLength: 200,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '说点什么…',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            IconButton(
              onPressed: _sendChat,
              icon: const Icon(Icons.send, size: 18, color: Color(0xFF8AB8FF)),
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
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _leave, child: const Text('退出房间')),
          ],
        ),
      ),
    );
  }
}
