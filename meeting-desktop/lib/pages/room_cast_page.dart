import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/cast_session.dart';
import '../services/ws_service.dart';

/// 单房间投放控制:
/// - PC 屏幕/窗口共享(LiveKit 推流) 或 上传文件投放(存服务器, 会议结束后删除)
/// - 投放前检查已有投放, 提示先停止当前投放
/// - PC 可控制房间内全部手机端: 播放/暂停/拖动进度/明暗/音量
/// - 房间设置开关(视频通话/摄像头)、会议时长、成员就位、点赞实时展示、关闭房间
class RoomCastPage extends StatefulWidget {
  final int roomId;

  const RoomCastPage({super.key, required this.roomId});

  @override
  State<RoomCastPage> createState() => _RoomCastPageState();
}

class _RoomCastPageState extends State<RoomCastPage> {
  final DesktopWsService _ws = DesktopWsService();
  RoomModel? _room;
  CastSession? _session;
  Timer? _refreshTimer;
  int _likeFlash = 0;
  double? _seekPreview;
  double _remoteBrightness = 0.5;
  double _remoteVolume = 0.5;

  @override
  void initState() {
    super.initState();
    _init();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refreshRoom());
  }

  Future<void> _init() async {
    await _refreshRoom();
    final room = _room;
    if (room == null) return;
    _ws.connect(onDashboardEvent: (_) {});
    _ws.subscribeRoom(room.roomCode, _onRoomEvent);
    try {
      final session = await CastManager.instance.ensureSession(widget.roomId);
      session.addListener(_onSessionChanged);
      if (mounted) setState(() => _session = session);
    } catch (error) {
      _showToast('媒体连接失败: $error');
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshRoom() async {
    try {
      final room = await ApiClient.instance.getRoom(widget.roomId);
      if (mounted) setState(() => _room = room);
    } catch (_) {}
  }

  void _onRoomEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    switch (type) {
      case 'PLAYBACK_CONTROL':
        // 播放控制指令(手机端或 PC 端发起) -> 本房间独立播放器执行
        _session?.applyPlaybackCommand(data);
        _refreshRoom();
        break;
      case 'LIKE':
        setState(() => _likeFlash++);
        _refreshRoom();
        break;
      case 'ROOM_RUNNING':
        _showToast('全部客户已就位, 该房间已运行');
        _refreshRoom();
        break;
      case 'MEMBER_JOINED':
      case 'MEMBER_LEFT':
      case 'SETTINGS_CHANGED':
      case 'CONTENT_CAST':
      case 'CAST_STOPPED':
      case 'COUNTDOWN_REMINDER':
        _refreshRoom();
        break;
      case 'RECORDING_DETECTED':
        _showToast('警告: 手机端检测到录屏行为!');
        break;
      case 'ROOM_CLOSED':
        _showToast('房间已关闭');
        _refreshRoom();
        break;
      default:
        break;
    }
  }

  // ---------- 投放操作 ----------

  bool get _hasActiveCast =>
      _room?.contentId != null ||
      _room?.screenSharing == true ||
      _session?.publishing == true;

  /// 投放前冲突检查: 已有投放时提示先停止, 用户确认后停止旧投放再继续
  Future<bool> _confirmReplaceCast() async {
    if (!_hasActiveCast) return true;
    final currentName = _room?.contentName ??
        (_room?.screenSharing == true || _session?.mode == CastMode.screen
            ? '屏幕/窗口投屏'
            : '当前投放');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('房间已有投放'),
        content: Text('该房间正在投放「$currentName」。\n需要先停止当前投放, 才能投放新内容。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('停止当前投放并继续')),
        ],
      ),
    );
    if (confirmed != true) return false;
    await _stopCast(silent: true);
    return true;
  }

  Future<void> _pickScreenSource({bool checkConflict = true}) async {
    final session = _session;
    if (session == null) return;
    if (checkConflict && !await _confirmReplaceCast()) return;
    final sources = await session.listCaptureSources();
    if (!mounted) return;
    final selected = await showDialog<webrtc.DesktopCapturerSource>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('选择投屏源(整屏或指定窗口)'),
        children: [
          for (final source in sources)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(source),
              child: Row(
                children: [
                  Icon(
                      source.type == webrtc.SourceType.Screen
                          ? Icons.desktop_windows
                          : Icons.window,
                      size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(source.name, maxLines: 1)),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      try {
        await session.startScreenCast(selected);
        // 服务端登记屏幕共享状态, 其他端冲突检查可感知
        await ApiClient.instance
            .startScreenShare(widget.roomId, replace: true);
      } catch (error) {
        await session.stopCast();
        _showToast('投屏启动失败: $error');
        return;
      }
      await _refreshRoom();
      _showToast('已开始投屏: ${selected.name}');
    }
  }

  static const _mediaExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts',
    'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma',
  };

  Future<void> _pickLocalFile() async {
    final session = _session;
    if (session == null) return;
    if (!await _confirmReplaceCast()) return;
    // 所有类型文件均可投放
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择投放文件(所有类型, 上传服务器保存, 会议结束后删除)',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final name = path.split(RegExp(r'[\\/]')).last;
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    // 1) 真实文件上传到服务器存储并投放(手机端/管理网页可直接打开, 会议结束后自动删除)
    _showToast('正在上传: $name ...');
    late final ContentModel content;
    try {
      content = await ApiClient.instance
          .uploadContentFile(path, roomId: widget.roomId);
    } on ApiException catch (error) {
      _showToast('文件上传失败: ${error.message}');
      return;
    } catch (error) {
      _showToast('文件上传失败: $error');
      return;
    }
    try {
      await ApiClient.instance
          .castContent(widget.roomId, content.id, replace: true);
    } catch (error) {
      // 投放失败时删除刚上传的内容, 避免孤儿文件
      try {
        await ApiClient.instance.deleteContent(content.id);
      } catch (_) {}
      _showToast(error is ApiException && error.castConflict
          ? '投放冲突: ${error.message}'
          : '投放失败: $error');
      return;
    }

    // 2) 媒体文件: 本地播放器解码并捕获推流; 其他类型: 系统默认应用打开后可用窗口投屏
    try {
      if (_mediaExtensions.contains(extension)) {
        final sources = await session.listCaptureSources();
        final appWindow = sources.firstWhere(
          (source) =>
              source.type == webrtc.SourceType.Window &&
              source.name.contains('投屏会议'),
          orElse: () => sources.first,
        );
        await session.startFileCast(path, playerWindowSource: appWindow);
      } else {
        await launchUrl(Uri.file(path));
        _showToast('已用系统应用打开, 可选择该窗口进行投屏');
        await _pickScreenSource(checkConflict: false);
      }
    } catch (error) {
      // 本地推流失败时回滚服务器投放状态, 避免假的"已投放"
      try {
        await ApiClient.instance.stopCastContent(widget.roomId);
      } catch (_) {}
      _showToast('本地推流启动失败: $error');
      await _refreshRoom();
      return;
    }
    await _refreshRoom();
    _showToast('已投放文件: $name');
  }

  /// 打开服务器上存储的当前投放文件(使用服务端下发的带签名 token 的地址)
  Future<void> _openServerFile() async {
    final fileUrl = _room?.contentFileUrl;
    if (fileUrl == null) {
      _showToast('当前房间没有投放内容');
      return;
    }
    final url = ApiClient.instance.fileDownloadUrl(fileUrl);
    await launchUrl(Uri.parse(url));
  }

  /// 停止投放: 同时停止本地推流与服务器投放状态
  /// (无条件调用服务端停止, 不依赖本地轮询快照, 后端容忍无投放时的停止)
  Future<void> _stopCast({bool silent = false}) async {
    await _session?.stopCast();
    try {
      await ApiClient.instance.stopCastContent(widget.roomId);
    } on ApiException catch (error) {
      if (!silent) _showToast('停止服务器投放失败: ${error.message}');
    }
    try {
      await ApiClient.instance.stopScreenShare(widget.roomId);
    } on ApiException catch (_) {}
    await _refreshRoom();
    if (!silent) _showToast('已停止投放');
  }

  // ---------- PC 端播放控制(下发到房间内全部手机端) ----------

  Future<void> _sendPlayback(String action,
      {double? positionSeconds, double? value}) async {
    try {
      await ApiClient.instance.controlPlayback(widget.roomId, action,
          positionSeconds: positionSeconds, value: value);
      await _refreshRoom();
    } on ApiException catch (error) {
      _showToast('控制失败: ${error.message}');
    } catch (error) {
      _showToast('控制失败: $error');
    }
  }

  Future<void> _closeRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('结束会议'),
        content: const Text('确认关闭该房间? 全部成员将被移出, 入会凭证立即失效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认关闭')),
        ],
      ),
    );
    if (confirmed != true) return;
    await CastManager.instance.closeSession(widget.roomId);
    await ApiClient.instance.closeRoom(widget.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatClock(int? seconds) {
    if (seconds == null || seconds < 0) return '--:--';
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final h = seconds ~/ 3600;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _session?.removeListener(_onSessionChanged);
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final session = _session;
    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(room.roomCode,
                  style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: scheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Text(room.name, style: const TextStyle(fontSize: 17)),
          ],
        ),
        actions: [
          if (room.understaffedAlert)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                backgroundColor: Colors.red,
                label: Text('缺人预警', style: TextStyle(color: Colors.white)),
              ),
            ),
          Chip(
            avatar: Icon(
                room.running
                    ? Icons.play_circle
                    : room.closed
                        ? Icons.stop_circle
                        : Icons.hourglass_top,
                size: 16,
                color: room.running
                    ? Colors.greenAccent
                    : room.closed
                        ? Colors.redAccent
                        : Colors.orangeAccent),
            label: Text(room.running
                ? '已运行 剩 ${_formatClock(room.remainingSeconds)}'
                : room.closed
                    ? '已关闭'
                    : '等待就位 ${room.onlineMemberCount}/${room.maxMembers}'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧: 播放器预览 + 投放操作 + 播放控制
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(child: _buildPreview(session, scheme)),
                  const SizedBox(height: 12),
                  _buildCastButtons(room, session),
                  const SizedBox(height: 12),
                  _buildPlaybackControls(room, scheme),
                ],
              ),
            ),
          ),
          // 右侧: 当前投放 / 设置 / 成员 / 点赞
          SizedBox(
            width: 310,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCurrentCastCard(room, scheme),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        dense: true,
                        secondary: const Icon(Icons.videocam_outlined),
                        title: const Text('开放视频通话'),
                        value: room.videoCallEnabled,
                        onChanged: (value) async {
                          await ApiClient.instance.updateSettings(room.id,
                              videoCallEnabled: value);
                          _refreshRoom();
                        },
                      ),
                      SwitchListTile(
                        dense: true,
                        secondary: const Icon(Icons.camera_alt_outlined),
                        title: const Text('开放摄像头'),
                        value: room.cameraEnabled,
                        onChanged: (value) async {
                          await ApiClient.instance
                              .updateSettings(room.id, cameraEnabled: value);
                          _refreshRoom();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.group_outlined, size: 18),
                            const SizedBox(width: 6),
                            const Text('成员就位',
                                style:
                                    TextStyle(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text(
                                '${room.onlineMemberCount}/${room.maxMembers}',
                                style: TextStyle(
                                    color: room.onlineMemberCount >=
                                            room.maxMembers
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final member in room.members)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.circle,
                                size: 10,
                                color: member.online
                                    ? Colors.green
                                    : Colors.grey),
                            title: Text(member.nickname),
                            subtitle: Text(member.identity,
                                style: const TextStyle(fontSize: 10)),
                          ),
                        if (room.members.isEmpty)
                          const Text('暂无成员',
                              style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.favorite,
                        color: _likeFlash.isEven
                            ? Colors.pinkAccent
                            : Colors.pink.shade200),
                    title: Text('点赞 ${room.likeCount}'),
                    subtitle: const Text('手机端点赞实时同步并入库记录',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.withValues(alpha: 0.08),
                  child: ListTile(
                    leading:
                        const Icon(Icons.meeting_room, color: Colors.redAccent),
                    title: const Text('结束会议'),
                    subtitle: const Text('全部成员移出, 上传文件删除',
                        style: TextStyle(fontSize: 11)),
                    enabled: !room.closed,
                    onTap: room.closed ? null : _closeRoom,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(CastSession? session, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: session?.publishing == true
              ? scheme.primary.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: session?.videoController != null
          ? Video(controller: session!.videoController!)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      session?.mode == CastMode.screen
                          ? Icons.screen_share
                          : Icons.cast,
                      size: 48,
                      color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    session?.mode == CastMode.screen
                        ? '屏幕/窗口投屏中'
                        : '未投放 — 选择屏幕共享或上传文件投放',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCastButtons(RoomModel room, CastSession? session) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: session == null ? null : _pickScreenSource,
          icon: const Icon(Icons.screen_share),
          label: const Text('屏幕/窗口共享'),
        ),
        FilledButton.tonalIcon(
          onPressed: session == null ? null : _pickLocalFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('上传文件投放'),
        ),
        FilledButton.tonalIcon(
          onPressed: _openServerFile,
          icon: const Icon(Icons.file_open),
          label: const Text('打开服务器文件'),
        ),
        OutlinedButton.icon(
          onPressed: _hasActiveCast ? _stopCast : null,
          icon: const Icon(Icons.stop_screen_share),
          label: const Text('停止投放'),
        ),
      ],
    );
  }

  /// PC 端播放控制区: 播放/暂停/进度 + 手机端明暗/音量远程调节
  Widget _buildPlaybackControls(RoomModel room, ColorScheme scheme) {
    final playing = room.playbackState == 'PLAYING';
    final duration = (room.contentDurationSeconds ?? 0).toDouble();
    final maxSeconds = duration > 0 ? duration : 3600.0;
    final position =
        (_seekPreview ?? room.playbackPositionSeconds).clamp(0.0, maxSeconds);
    final controlsEnabled = room.running && room.contentId != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.settings_remote, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text('播放控制(下发到全部手机端)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  '状态: ${room.playbackState}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: !controlsEnabled
                      ? null
                      : () => _sendPlayback(playing ? 'PAUSE' : 'PLAY'),
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Text(_formatClock(position.toInt()),
                    style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: position,
                    max: maxSeconds,
                    onChanged: !controlsEnabled
                        ? null
                        : (value) => setState(() => _seekPreview = value),
                    onChangeEnd: !controlsEnabled
                        ? null
                        : (value) {
                            setState(() => _seekPreview = null);
                            _sendPlayback('SEEK', positionSeconds: value);
                          },
                  ),
                ),
                Text(
                    duration > 0
                        ? _formatClock(duration.toInt())
                        : _formatClock(room.playbackPositionSeconds.toInt()),
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.brightness_6, size: 16),
                Expanded(
                  child: Slider(
                    value: _remoteBrightness,
                    onChanged: !room.running
                        ? null
                        : (value) => setState(() => _remoteBrightness = value),
                    onChangeEnd: !room.running
                        ? null
                        // 后端统一 0~100
                        : (value) =>
                            _sendPlayback('BRIGHTNESS', value: value * 100),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.volume_up, size: 16),
                Expanded(
                  child: Slider(
                    value: _remoteVolume,
                    onChanged: !room.running
                        ? null
                        : (value) => setState(() => _remoteVolume = value),
                    onChangeEnd: !room.running
                        ? null
                        : (value) =>
                            _sendPlayback('VOLUME', value: value * 100),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCastCard(RoomModel room, ColorScheme scheme) {
    final casting = room.contentId != null;
    return Card(
      color: casting ? scheme.primary.withValues(alpha: 0.10) : null,
      child: ListTile(
        leading: Icon(casting ? Icons.cast_connected : Icons.cast,
            color: casting ? scheme.primary : Colors.white38),
        title: Text(casting ? (room.contentName ?? '投放中') : '暂无投放内容'),
        subtitle: Text(
          casting
              ? '播放 ${room.playbackState} @ ${_formatClock(room.playbackPositionSeconds.toInt())}'
              : '选择屏幕共享或上传文件开始投放',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
