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
/// - 屏幕/窗口投屏 或 本地视频文件投放(独立播放器实例)
/// - 响应手机端 播放/暂停/拖进度条 指令
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
        // 手机端播放控制指令 -> 本房间独立播放器执行
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

  Future<void> _pickScreenSource() async {
    final session = _session;
    if (session == null) return;
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
      await session.startScreenCast(selected);
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
    try {
      final content = await ApiClient.instance
          .uploadContentFile(path, roomId: widget.roomId);
      await ApiClient.instance.castContent(widget.roomId, content.id);
    } catch (error) {
      _showToast('文件上传失败: $error');
      return;
    }

    // 2) 媒体文件: 本地播放器解码并捕获推流; 其他类型: 系统默认应用打开后可用窗口投屏
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
      await _pickScreenSource();
    }
    await _refreshRoom();
    _showToast('已投放文件: $name');
  }

  /// 打开服务器上存储的当前投放文件
  Future<void> _openServerFile() async {
    final contentId = _room?.contentId;
    if (contentId == null) {
      _showToast('当前房间没有投放内容');
      return;
    }
    final url = ApiClient.instance.fileDownloadUrl(contentId);
    await launchUrl(Uri.parse(url));
  }

  Future<void> _stopCast() async {
    await _session?.stopCast();
    _showToast('已停止投放');
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${room.name} · ${room.roomCode}'),
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
          // 左侧: 播放器预览 + 投放操作
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: session?.videoController != null
                          ? Video(controller: session!.videoController!)
                          : Center(
                              child: Text(
                                session?.mode == CastMode.screen
                                    ? '屏幕/窗口投屏中'
                                    : '未投放 — 选择屏幕投屏或文件投放(所有类型)',
                                style:
                                    const TextStyle(color: Colors.white38),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed:
                            session == null ? null : _pickScreenSource,
                        icon: const Icon(Icons.screen_share),
                        label: const Text('屏幕/窗口投屏'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: session == null ? null : _pickLocalFile,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('文件投放(所有类型)'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _openServerFile,
                        icon: const Icon(Icons.file_open),
                        label: const Text('打开服务器文件'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: session?.publishing == true ? _stopCast : null,
                        icon: const Icon(Icons.stop_screen_share),
                        label: const Text('停止投放'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700),
                        onPressed: room.closed ? null : _closeRoom,
                        icon: const Icon(Icons.meeting_room),
                        label: const Text('结束会议'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '播放状态: ${room.playbackState} @ ${_formatClock(room.playbackPositionSeconds.toInt())}'
                    '${session?.filePath != null ? '  |  文件: ${session!.filePath}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          // 右侧: 设置 / 成员 / 点赞
          SizedBox(
            width: 300,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        dense: true,
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
                        const Text('成员就位 (仅手机客户端)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
