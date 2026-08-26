import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/cast_session.dart';
import '../services/ws_service.dart';

/// 单房间推流控制:
/// - 每个房间可独立选择推流源: 屏幕/窗口共享、本地视频推流、摄像头推流(均走 LiveKit 实时流)
/// - 推流前检查已有推流, 提示先停止当前推流
/// - 本地视频在独立播放窗口后台播放推流, 退出本页/切到其他房间不中断;
///   本页提供播放/暂停/进度控制(转发给播放窗口)
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
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

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
    _loadChatHistory();
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
    if (!mounted) return;
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    switch (type) {
      case 'LIKE':
        setState(() => _likeFlash++);
        _refreshRoom();
        break;
      case 'ROOM_RUNNING':
        _showToast('首次推流开始, 会议已开始计时');
        _refreshRoom();
        break;
      case 'CHAT_MESSAGE':
        setState(() {
          _chatMessages.add(data);
          if (_chatMessages.length > 100) _chatMessages.removeAt(0);
        });
        _scrollChatToEnd();
        break;
      case 'MEMBER_JOINED':
      case 'MEMBER_LEFT':
      case 'SETTINGS_CHANGED':
      case 'CAST_STARTED':
      case 'CAST_STOPPED':
      case 'COUNTDOWN_REMINDER':
        _refreshRoom();
        break;
      case 'RECORDING_DETECTED':
        _showToast('警告: 手机端检测到录屏行为!');
        break;
      case 'JOIN_REQUEST':
        _showToast('新入会申请: ${data['nickname'] ?? ''}, 请审批');
        _refreshRoom();
        break;
      case 'JOIN_APPROVED':
      case 'JOIN_REJECTED':
      case 'MEMBER_KICKED':
      case 'MEMBER_MUTED':
      case 'ALL_MUTED':
      case 'MEMBER_CAMERA_DISABLED':
      case 'ROOM_ACTIVATED':
        _refreshRoom();
        break;
      case 'ROOM_CLOSED':
        _showToast('房间已关闭');
        _refreshRoom();
        break;
      default:
        break;
    }
  }

  // ---------- 推流操作 ----------

  bool get _hasActiveCast =>
      _room?.casting == true || _session?.publishing == true;

  /// 推流前冲突检查: 已有推流时提示先停止, 用户确认后停止旧推流再继续
  Future<bool> _confirmReplaceCast() async {
    if (!_hasActiveCast) return true;
    final currentName =
        _room?.castDescription ?? _session?.sourceLabel ?? '当前推流';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('房间正在推流'),
        content: Text('该房间正在推流「$currentName」。\n需要先停止当前推流, 才能开始新推流。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('停止当前推流并继续')),
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
    if (sources.isEmpty) {
      _showToast('未枚举到可推流的屏幕/窗口, 请检查系统屏幕录制权限');
      return;
    }
    final selected = await showDialog<webrtc.DesktopCapturerSource>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('选择推流源(整屏或指定窗口)'),
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
        // 服务端登记推流状态, 其他端冲突检查可感知
        await ApiClient.instance.startCast(widget.roomId, 'SCREEN',
            label: selected.name, replace: true);
      } catch (error) {
        await session.stopCast();
        _showToast('推流启动失败: $error');
        return;
      }
      await _refreshRoom();
      _showToast('已开始推流: ${selected.name}');
    }
  }

  static const _videoExtensions = [
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts',
  ];

  /// 本地视频推流: 选择本地视频文件, 本地解码播放后经窗口捕获以实时流推给房间
  Future<void> _pickLocalVideo() async {
    final session = _session;
    if (session == null) return;
    if (!await _confirmReplaceCast()) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _videoExtensions,
      dialogTitle: '选择本地视频文件(实时推流, 不上传服务器)',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final name = path.split(RegExp(r'[\\/]')).last;

    try {
      await session.startVideoCast(path);
      await ApiClient.instance.startCast(widget.roomId, 'VIDEO',
          label: name, replace: true);
    } catch (error) {
      await session.stopCast();
      _showToast('视频推流启动失败: $error');
      await _refreshRoom();
      return;
    }
    await _refreshRoom();
    _showToast('已开始视频推流: $name');
  }

  /// 摄像头推流: 采集本机摄像头推给房间
  Future<void> _castCamera() async {
    final session = _session;
    if (session == null) return;
    if (!await _confirmReplaceCast()) return;
    try {
      await session.startCameraCast();
      await ApiClient.instance
          .startCast(widget.roomId, 'CAMERA', label: '摄像头', replace: true);
    } catch (error) {
      await session.stopCast();
      _showToast('摄像头推流启动失败: $error');
      await _refreshRoom();
      return;
    }
    await _refreshRoom();
    _showToast('已开始摄像头推流');
  }

  /// 停止推流: 同时停止本地推流与服务器推流登记
  Future<void> _stopCast({bool silent = false}) async {
    try {
      await _session?.stopCast();
    } catch (error) {
      if (!silent) _showToast('停止本地推流异常: $error');
    }
    try {
      await ApiClient.instance.stopCast(widget.roomId);
    } on ApiException catch (error) {
      if (!silent) _showToast('停止推流登记失败: ${error.message}');
    }
    await _refreshRoom();
    if (!silent) _showToast('已停止推流');
  }

  // ---------- 成员管理 ----------

  Future<void> _memberAction(Future<void> Function() action) async {
    try {
      await action();
      await _refreshRoom();
    } on ApiException catch (error) {
      _showToast('操作失败: ${error.message}');
    } catch (error) {
      _showToast('操作失败: $error');
    }
  }

  Future<void> _showAttendance() async {
    List<dynamic> rows;
    try {
      rows = await ApiClient.instance.attendance(widget.roomId);
    } catch (error) {
      _showToast('获取报表失败: $error');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('出席统计报表'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('昵称')),
                DataColumn(label: Text('座位')),
                DataColumn(label: Text('在线时长')),
                DataColumn(label: Text('入会次数')),
                DataColumn(label: Text('点赞')),
                DataColumn(label: Text('状态')),
              ],
              rows: [
                for (final row
                    in rows.whereType<Map<String, dynamic>>())
                  DataRow(cells: [
                    DataCell(Text('${row['nickname'] ?? ''}')),
                    DataCell(Text('${row['seatNo'] ?? '-'}')),
                    DataCell(Text(_formatClock(
                        (row['onlineSeconds'] as num?)?.toInt()))),
                    DataCell(Text('${row['joinCount'] ?? 0}')),
                    DataCell(Text('${row['likeCount'] ?? 0}')),
                    DataCell(Text(
                        row['online'] == true ? '在线' : '离线')),
                  ]),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  // ---------- 文字聊天 ----------

  Future<void> _loadChatHistory() async {
    try {
      final history = await ApiClient.instance.chatHistory(widget.roomId);
      if (!mounted) return;
      setState(() {
        _chatMessages
          ..clear()
          ..addAll(history.whereType<Map<String, dynamic>>());
      });
      _scrollChatToEnd();
    } catch (_) {}
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendChat() async {
    final content = _chatController.text.trim();
    if (content.isEmpty) return;
    _chatController.clear();
    try {
      await ApiClient.instance.sendChat(widget.roomId, content);
    } on ApiException catch (error) {
      _showToast('发送失败: ${error.message}');
    } catch (error) {
      _showToast('发送失败: $error');
    }
  }

  Future<void> _showLikeRecords() async {
    List<dynamic> rows;
    try {
      rows = await ApiClient.instance.listLikes(widget.roomId);
    } catch (error) {
      _showToast('获取点赞记录失败: $error');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('点赞记录 (${rows.length})'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: rows.isEmpty
              ? const Center(
                  child: Text('暂无点赞记录',
                      style: TextStyle(color: Colors.white38)))
              : ListView(
                  children: [
                    for (final row in rows.whereType<Map<String, dynamic>>())
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.favorite,
                            color: Colors.pinkAccent, size: 18),
                        title: Text('${row['nickname'] ?? ''}'),
                        subtitle: Text('${row['memberIdentity'] ?? ''}',
                            style: const TextStyle(fontSize: 10)),
                        trailing: Text(
                            '${row['likedAt'] ?? ''}'
                                .replaceFirst('T', ' ')
                                .split('.')
                                .first,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54)),
                      ),
                  ],
                ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
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
    // 先请求服务端关房, 成功后再停止本地推流;
    // 服务端失败时保留推流, 避免房间还开着但推流已断
    try {
      await ApiClient.instance.closeRoom(widget.roomId);
    } catch (error) {
      _showToast('关闭房间失败: $error');
      return;
    }
    await CastManager.instance.closeSession(widget.roomId);
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
    _chatController.dispose();
    _chatScroll.dispose();
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
                  if (session?.mode == CastMode.video) ...[
                    const SizedBox(height: 12),
                    _buildLocalPlayerControls(session!, scheme),
                  ],
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
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _memberAction(() => ApiClient
                                  .instance
                                  .muteAll(room.id, !room.allMuted)),
                              icon: Icon(
                                  room.allMuted
                                      ? Icons.mic
                                      : Icons.mic_off,
                                  size: 15),
                              label: Text(
                                  room.allMuted ? '解除全员静音' : '全员静音'),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _showAttendance,
                              icon: const Icon(Icons.bar_chart, size: 15),
                              label: const Text('出席报表'),
                            ),
                          ],
                        ),
                        for (final member in room.members)
                          if (!member.kicked)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.circle,
                                  size: 10,
                                  color: !member.approved
                                      ? Colors.orange
                                      : member.online
                                          ? Colors.green
                                          : Colors.grey),
                              title: Text(
                                  '${member.seatNo != null ? '${member.seatNo}号 · ' : ''}${member.nickname}'
                                  '${member.approved ? '' : ' (待审批)'}'),
                              subtitle: Text(member.identity,
                                  style: const TextStyle(fontSize: 10)),
                              trailing: !member.approved
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: '批准入会',
                                          iconSize: 17,
                                          icon: const Icon(Icons.check,
                                              color: Colors.greenAccent),
                                          onPressed: () => _memberAction(
                                              () => ApiClient.instance
                                                  .approveMember(room.id,
                                                      member.identity, true)),
                                        ),
                                        IconButton(
                                          tooltip: '拒绝入会',
                                          iconSize: 17,
                                          icon: const Icon(Icons.close,
                                              color: Colors.redAccent),
                                          onPressed: () => _memberAction(
                                              () => ApiClient.instance
                                                  .approveMember(room.id,
                                                      member.identity, false)),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: member.muted
                                              ? '取消静音'
                                              : '静音',
                                          iconSize: 17,
                                          icon: Icon(
                                              member.muted
                                                  ? Icons.mic_off
                                                  : Icons.mic,
                                              color: member.muted
                                                  ? Colors.orange
                                                  : Colors.white54),
                                          onPressed: () => _memberAction(
                                              () => ApiClient.instance
                                                  .muteMember(
                                                      room.id,
                                                      member.identity,
                                                      !member.muted)),
                                        ),
                                        IconButton(
                                          tooltip: member.cameraDisabled
                                              ? '允许摄像头'
                                              : '禁止摄像头',
                                          iconSize: 17,
                                          icon: Icon(
                                              member.cameraDisabled
                                                  ? Icons.videocam_off
                                                  : Icons.videocam,
                                              color: member.cameraDisabled
                                                  ? Colors.orange
                                                  : Colors.white54),
                                          onPressed: () => _memberAction(
                                              () => ApiClient.instance
                                                  .setMemberCamera(
                                                      room.id,
                                                      member.identity,
                                                      !member
                                                          .cameraDisabled)),
                                        ),
                                        IconButton(
                                          tooltip: '移出会议',
                                          iconSize: 17,
                                          icon: const Icon(
                                              Icons.person_remove,
                                              color: Colors.redAccent),
                                          onPressed: () => _memberAction(
                                              () => ApiClient.instance
                                                  .kickMember(room.id,
                                                      member.identity)),
                                        ),
                                      ],
                                    ),
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
                    subtitle: const Text('点击查看点赞记录列表',
                        style: TextStyle(fontSize: 11)),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: _showLikeRecords,
                  ),
                ),
                const SizedBox(height: 12),
                _buildChatCard(),
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.withValues(alpha: 0.08),
                  child: ListTile(
                    leading:
                        const Icon(Icons.meeting_room, color: Colors.redAccent),
                    title: const Text('结束会议'),
                    subtitle: const Text('全部成员移出, 推流停止',
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

  Widget _buildChatCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 18),
                SizedBox(width: 6),
                Text('文字聊天',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: _chatMessages.isEmpty
                  ? const Center(
                      child: Text('暂无消息',
                          style: TextStyle(color: Colors.white38)))
                  : ListView(
                      controller: _chatScroll,
                      children: [
                        for (final msg in _chatMessages)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 3),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12),
                                children: [
                                  TextSpan(
                                    text:
                                        '${msg['nickname'] ?? ''}${msg['fromAdmin'] == true ? ' (主持)' : ''}: ',
                                    style: TextStyle(
                                        color: msg['fromAdmin'] == true
                                            ? Colors.orangeAccent
                                            : Colors.lightBlueAccent,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(
                                      text: '${msg['content'] ?? ''}',
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: '发送消息到房间...',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: _sendChat,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
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
      child: _buildPreviewPlaceholder(session, scheme),
    );
  }

  Widget _buildPreviewPlaceholder(CastSession? session, ColorScheme scheme) {
    final (icon, text) = switch (session?.mode) {
      CastMode.screen => (Icons.screen_share, '屏幕/窗口推流中'),
      CastMode.video => (
        Icons.movie_outlined,
        '本地视频推流中 — 独立播放窗口后台播放, 切换房间不中断'
      ),
      CastMode.camera => (Icons.videocam, '摄像头推流中'),
      _ => (Icons.cast, '未推流 — 选择屏幕共享、本地视频或摄像头开始推流'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.white38)),
        ],
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
          onPressed: session == null ? null : _pickLocalVideo,
          icon: const Icon(Icons.movie_outlined),
          label: const Text('本地视频推流'),
        ),
        FilledButton.tonalIcon(
          onPressed: session == null ? null : _castCamera,
          icon: const Icon(Icons.videocam_outlined),
          label: const Text('摄像头推流'),
        ),
        OutlinedButton.icon(
          onPressed: _hasActiveCast ? _stopCast : null,
          icon: const Icon(Icons.stop_screen_share),
          label: const Text('停止推流'),
        ),
      ],
    );
  }

  /// 本地视频推流控制区: 播放/暂停/进度指令转发给独立播放窗口
  Widget _buildLocalPlayerControls(CastSession session, ColorScheme scheme) {
    final playing = session.playerPlaying;
    final duration = session.playerDurationMs / 1000.0;
    final maxSeconds = duration > 0 ? duration : 1.0;
    final position = (_seekPreview ?? session.playerPositionMs / 1000.0)
        .clamp(0.0, maxSeconds);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.movie_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(session.sourceLabel ?? '本地视频',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Text('后台推流中',
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: session.playerPlayPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Text(_formatClock(position.toInt()),
                    style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: position,
                    max: maxSeconds,
                    onChanged: (value) =>
                        setState(() => _seekPreview = value),
                    onChangeEnd: (value) {
                      setState(() => _seekPreview = null);
                      session.playerSeek((value * 1000).round());
                    },
                  ),
                ),
                Text(_formatClock(duration.toInt()),
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCastCard(RoomModel room, ColorScheme scheme) {
    final casting = room.casting || _session?.publishing == true;
    final description =
        room.castDescription ?? _session?.sourceLabel ?? '推流中';
    return Card(
      color: casting ? scheme.primary.withValues(alpha: 0.10) : null,
      child: ListTile(
        leading: Icon(casting ? Icons.cast_connected : Icons.cast,
            color: casting ? scheme.primary : Colors.white38),
        title: Text(casting ? description : '暂无推流'),
        subtitle: Text(
          casting
              ? (room.castBy == null ? '实时推流中' : '由 ${room.castBy} 发起')
              : '选择屏幕共享、本地视频或摄像头开始推流',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
