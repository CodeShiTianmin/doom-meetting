import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/ws_service.dart';
import 'room_cast_page.dart';

/// 房间总览(固定 1-20 号房):
/// 每张房卡显示房号/人员信息/点赞/房间状态/会议倒计时(绿色, 最后 60 秒变红),
/// 外置操作按钮: 手动结束会议(重置) / 摄像头权限(默认关闭) / 二维码获取。
/// 点击房卡空白处进入单房推流页面。
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final DesktopWsService _ws = DesktopWsService();
  List<RoomModel> _rooms = [];
  Timer? _refreshTimer;
  Timer? _tickTimer;

  /// 最近一次刷新到的剩余秒数, 由本地秒级递减驱动倒计时显示
  DateTime _lastRefreshAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refresh();
    _ws.connect(onDashboardEvent: _onDashboardEvent);
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    // 秒级重绘驱动倒计时显示
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    _ws.disconnect();
    CastManager.instance.closeAll();
    super.dispose();
  }

  void _onDashboardEvent(Map<String, dynamic> event) {
    // 手机端播放控制指令: 转发给统一播放器执行
    if (event['type'] == 'CAST_CONTROL') {
      final payload = event['payload'];
      if (payload is Map<String, dynamic>) {
        CastManager.instance.handleRemoteControl(payload);
      }
      return;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rooms = await ApiClient.instance.listRooms();
      // 固定房号 1-20 按数字排序显示
      rooms.sort((a, b) => (int.tryParse(a.roomCode) ?? 0)
          .compareTo(int.tryParse(b.roomCode) ?? 0));
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _lastRefreshAt = DateTime.now();
        });
      }
    } catch (_) {}
  }

  /// 本地推算的剩余秒数(刷新间隔内按秒递减)
  int? _remainingSeconds(RoomModel room) {
    final base = room.remainingSeconds;
    if (base == null) return null;
    final elapsed = DateTime.now().difference(_lastRefreshAt).inSeconds;
    final remaining = base - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  void _showQr(RoomModel room) {
    showDialog<void>(
      context: context,
      builder: (_) => _QrDialog(room: room),
    );
  }

  /// 手动结束会议: 恢复房间推流后的初始状态, 旧二维码凭证失效
  Future<void> _resetRoom(RoomModel room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('结束会议 · ${room.roomCode} 号房间'),
        content: const Text('结束后房间恢复初始状态, 当前客户码/服务码将失效并重新签发。确定结束吗?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束会议'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.resetRoom(room.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  /// 摄像头权限开关(默认关闭, 在总览界面按房间开放)
  Future<void> _toggleCamera(RoomModel room) async {
    try {
      await ApiClient.instance
          .updateSettings(room.id, cameraEnabled: !room.cameraEnabled);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('惊喜影视平台 — 房间总览'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: _rooms.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 216,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return _RoomCard(
                  room: room,
                  remainingSeconds: _remainingSeconds(room),
                  onOpen: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => RoomCastPage(roomId: room.id)))
                      .then((_) => _refresh()),
                  onShowQr: () => _showQr(room),
                  onReset: () => _resetRoom(room),
                  onToggleCamera: () => _toggleCamera(room),
                );
              },
            ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final int? remainingSeconds;
  final VoidCallback onOpen;
  final VoidCallback onShowQr;
  final VoidCallback onReset;
  final VoidCallback onToggleCamera;

  const _RoomCard({
    required this.room,
    required this.remainingSeconds,
    required this.onOpen,
    required this.onShowQr,
    required this.onReset,
    required this.onToggleCamera,
  });

  static String _formatRemaining(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = room.running
        ? Colors.green
        : room.closed
            ? Colors.grey
            : Colors.orange;
    final remaining = remainingSeconds;
    // 倒计时绿色显示, 会议最后 60 秒字体变红
    final countdownColor =
        (remaining != null && remaining <= 60) ? Colors.red : Colors.green;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        // 按房间空白处进入单房推流界面
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${room.roomCode} 号房间',
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
                          ? '正在运行'
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
                  const Icon(Icons.people, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      room.members.where((m) => m.online).isEmpty
                          ? '${room.onlineMemberCount}/${room.maxMembers} 就位'
                          : '${room.onlineMemberCount}/${room.maxMembers} 就位 · '
                              '${room.members.where((m) => m.online).map((m) => m.nickname).join('、')}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.favorite,
                      size: 14, color: Colors.pinkAccent),
                  const SizedBox(width: 4),
                  Text('点赞 ${room.likeCount}',
                      style: const TextStyle(fontSize: 12)),
                  if (room.running && remaining != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.timer_outlined, size: 14, color: countdownColor),
                    const SizedBox(width: 4),
                    Text(_formatRemaining(remaining),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: countdownColor)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(room.casting ? Icons.cast_connected : Icons.cast,
                      size: 13,
                      color: room.casting
                          ? const Color(0xFF5B8DEF)
                          : Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      room.casting ? '推流中: ${room.castLabel ?? ''}' : '暂无推流',
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    tooltip: '手动结束会议(恢复初始状态)',
                    visualDensity: VisualDensity.compact,
                    onPressed: onReset,
                    icon: const Icon(Icons.stop_circle_outlined,
                        size: 20, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: room.cameraEnabled ? '关闭摄像头权限' : '开放摄像头权限',
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggleCamera,
                    icon: Icon(
                      room.cameraEnabled
                          ? Icons.videocam
                          : Icons.videocam_off_outlined,
                      size: 20,
                      color: room.cameraEnabled
                          ? Colors.green
                          : Colors.white38,
                    ),
                  ),
                  IconButton(
                    tooltip: '二维码获取',
                    visualDensity: VisualDensity.compact,
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code, size: 20),
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

/// 单房二维码获取界面:
/// 显示房号, 二维码上方备注「客户码1」「服务码2」, 各配复制按钮。
/// 关闭对话框不影响凭证有效性, 可反复调取; 仅手动结束会议后失效。
class _QrDialog extends StatelessWidget {
  final RoomModel room;

  const _QrDialog({required this.room});

  static const List<String> _seatLabels = ['客户码1', '服务码2'];

  String _labelOf(SeatInviteModel invite, int index) {
    final seatNo = invite.seatNo;
    if (seatNo != null && seatNo >= 1 && seatNo <= _seatLabels.length) {
      return _seatLabels[seatNo - 1];
    }
    return index < _seatLabels.length ? _seatLabels[index] : '凭证${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final invites = room.invites.where((invite) => !invite.revoked).toList();
    return AlertDialog(
      title: Text('二维码获取 · ${room.roomCode} 号房间'),
      content: SizedBox(
        width: 560,
        child: invites.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无有效凭证, 请手动结束会议后重新签发'),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < invites.length; i++)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_labelOf(invites[i], i),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (invites[i].inviteUrl != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: QrImageView(
                                data: invites[i].inviteUrl!, size: 190),
                          ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            final url = invites[i].inviteUrl;
                            if (url == null) return;
                            await Clipboard.setData(ClipboardData(text: url));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('${_labelOf(invites[i], i)} 已复制')));
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text('复制${_labelOf(invites[i], i)}'),
                        ),
                      ],
                    ),
                ],
              ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭')),
      ],
    );
  }
}
