import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/ws_service.dart';
import 'room_cast_page.dart';

/// 房间总览: 房间卡片(状态/就位/红灯预警/点赞/剩余时长) + 创建房间 + 二维码
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final DesktopWsService _ws = DesktopWsService();
  List<RoomModel> _rooms = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _ws.connect(onDashboardEvent: (_) => _refresh());
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ws.disconnect();
    CastManager.instance.closeAll();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rooms = await ApiClient.instance.listRooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {}
  }

  Future<void> _createRoom() async {
    final created = await showDialog<RoomModel>(
      context: context,
      builder: (_) => const _CreateRoomDialog(),
    );
    if (created != null) {
      await _refresh();
      if (mounted) _showQr(created);
    }
  }

  void _showQr(RoomModel room) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('邀请二维码 · ${room.roomCode}'),
        content: SizedBox(
          width: room.invites.isNotEmpty ? 720 : 320,
          height: room.invites.isNotEmpty ? 340 : 420,
          child: room.invites.isNotEmpty
              // 每个座位独立二维码: 横向排列, 分别发给不同客户, 一码一人
              ? Column(
                  children: [
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final invite in room.invites)
                            Container(
                              width: 220,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('座位 ${invite.seatNo ?? '-'}'
                                      '${invite.used ? ' (已使用)' : ''}'),
                                  const SizedBox(height: 6),
                                  if (invite.inviteUrl != null)
                                    Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(10),
                                      child: QrImageView(
                                          data: invite.inviteUrl!,
                                          size: 180),
                                    ),
                                  const SizedBox(height: 4),
                                  SelectableText(invite.inviteUrl ?? '',
                                      maxLines: 2,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white54)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('每个座位一张二维码, 分别发给不同客户扫码入会',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (room.qrContent != null)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(data: room.qrContent!, size: 220),
                      ),
                    const SizedBox(height: 8),
                    SelectableText(room.inviteUrl ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 4),
                    const Text('截图后经微信等渠道发给客户, 客户扫码即可匿名入会',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final updated =
                  await ApiClient.instance.regenerateInvite(room.id);
              if (mounted) {
                Navigator.of(context).pop();
                _showQr(updated);
              }
            },
            child: const Text('重新生成凭证'),
          ),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _deleteRoom(RoomModel room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除房间 · ${room.name}'),
        content: const Text('删除后房间及成员/点赞/聊天/事件记录将全部清除, 不可恢复。'
            '\n未结束的会议会先自动结束。确定删除?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CastManager.instance.closeSession(room.id);
      await ApiClient.instance.deleteRoom(room.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间总览 — 多房并发推流'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRoom,
        icon: const Icon(Icons.add),
        label: const Text('创建房间'),
      ),
      body: _rooms.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.meeting_room_outlined,
                      size: 64, color: Colors.white24),
                  SizedBox(height: 12),
                  Text('暂无房间 — 点击右下角创建房间开始会议',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 216,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _rooms.length,
              itemBuilder: (context, index) => _RoomCard(
                room: _rooms[index],
                onOpen: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) =>
                            RoomCastPage(roomId: _rooms[index].id)))
                    .then((_) => _refresh()),
                onShowQr: () => _showQr(_rooms[index]),
                onDelete: () => _deleteRoom(_rooms[index]),
              ),
            ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onOpen;
  final VoidCallback onShowQr;
  final VoidCallback onDelete;

  const _RoomCard(
      {required this.room,
      required this.onOpen,
      required this.onShowQr,
      required this.onDelete});

  static String _formatRemaining(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '剩 $m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = room.running
        ? Colors.green
        : room.closed
            ? Colors.grey
            : Colors.orange;
    return Card(
      // 缺人超过阈值: 红灯预警
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: room.understaffedAlert
            ? const BorderSide(color: Colors.red, width: 2)
            : BorderSide(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (room.understaffedAlert)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.warning_amber,
                          color: Colors.red, size: 20),
                    ),
                  Expanded(
                    child: Text(room.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                    side: BorderSide(color: statusColor),
                    label: Text(
                      room.running
                          ? '已运行'
                          : room.closed
                              ? '已关闭'
                              : '等待就位',
                      style: TextStyle(fontSize: 11, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.tag, size: 13, color: Colors.white38),
                  const SizedBox(width: 3),
                  Text(room.roomCode,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 1.2)),
                  if (room.running && room.remainingSeconds != null) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.timer_outlined,
                        size: 13, color: Colors.white38),
                    const SizedBox(width: 3),
                    Text(_formatRemaining(room.remainingSeconds!),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.people, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text('${room.onlineMemberCount}/${room.maxMembers} 就位',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                  const Icon(Icons.favorite,
                      size: 14, color: Colors.pinkAccent),
                  const SizedBox(width: 4),
                  Text('${room.likeCount}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                      room.casting
                          ? Icons.cast_connected
                          : Icons.cast,
                      size: 13,
                      color: room.casting
                          ? const Color(0xFF5B8DEF)
                          : Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      room.casting
                          ? '推流中: ${room.castDescription}'
                          : '暂无推流',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('二维码'),
                  ),
                  IconButton(
                    tooltip: '删除房间',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.cast, size: 16),
                    label: const Text('推流控制'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 创建房间: 名称 + 会议时长 + 视频通话/摄像头开关
class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog();

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _nameController = TextEditingController();
  int _durationMinutes = 60;
  int _maxMembers = 2;
  bool _videoCallEnabled = true;
  bool _cameraEnabled = true;
  bool _approvalRequired = false;
  DateTime? _scheduledStartAt;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final room = await ApiClient.instance.createRoom(
        name: _nameController.text.trim(),
        durationMinutes: _durationMinutes,
        maxMembers: _maxMembers,
        videoCallEnabled: _videoCallEnabled,
        cameraEnabled: _cameraEnabled,
        approvalRequired: _approvalRequired,
        scheduledStartAt: _scheduledStartAt?.toIso8601String(),
      );
      if (mounted) Navigator.of(context).pop(room);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建房间'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: '房间名称', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('会议时长'),
                Expanded(
                  child: Slider(
                    value: _durationMinutes.toDouble(),
                    min: 10,
                    max: 240,
                    divisions: 23,
                    label: '$_durationMinutes 分钟',
                    onChanged: (value) =>
                        setState(() => _durationMinutes = value.round()),
                  ),
                ),
                Text('$_durationMinutes 分'),
              ],
            ),
            Row(
              children: [
                const Text('成员数上限'),
                Expanded(
                  child: Slider(
                    value: _maxMembers.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_maxMembers 人',
                    onChanged: (value) =>
                        setState(() => _maxMembers = value.round()),
                  ),
                ),
                Text('$_maxMembers 人'),
              ],
            ),
            SwitchListTile(
              dense: true,
              title: const Text('开放视频通话'),
              value: _videoCallEnabled,
              onChanged: (value) => setState(() => _videoCallEnabled = value),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('开放摄像头'),
              value: _cameraEnabled,
              onChanged: (value) => setState(() => _cameraEnabled = value),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('开启等候室(入会需审批)'),
              value: _approvalRequired,
              onChanged: (value) =>
                  setState(() => _approvalRequired = value),
            ),
            ListTile(
              dense: true,
              title: Text(_scheduledStartAt == null
                  ? '预约开会时间(可选, 不选则立即开会)'
                  : '预约: $_scheduledStartAt'),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (date == null || !mounted) return;
                final time = await showTimePicker(
                    context: this.context, initialTime: TimeOfDay.now());
                if (time == null) return;
                setState(() => _scheduledStartAt = DateTime(date.year,
                    date.month, date.day, time.hour, time.minute));
              },
              onLongPress: () => setState(() => _scheduledStartAt = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: _submitting ? null : _submit, child: const Text('创建')),
      ],
    );
  }
}
