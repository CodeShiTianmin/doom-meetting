import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/ws_service.dart';
import 'login_page.dart';
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
  bool _loading = true;
  bool _refreshing = false;
  bool _loggingOut = false;
  String? _error;
  Timer? _refreshTimer;
  Timer? _tickTimer;

  /// 正在执行操作的房间 id, 防止重复点击
  final Set<int> _busyRooms = {};

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
      if (mounted && _rooms.any((room) => room.running)) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    _ws.dispose();
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
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rooms = await ApiClient.instance.listRooms();
      // 固定房号 1-20 按数字排序显示
      rooms.sort((a, b) => (int.tryParse(a.roomCode) ?? 0)
          .compareTo(int.tryParse(b.roomCode) ?? 0));
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _error = null;
          _loading = false;
          _lastRefreshAt = DateTime.now();
        });
      }
      // 结束会议重置/超时关闭的房间同步加入/退出统一推流
      unawaited(CastManager.instance.syncRooms(rooms));
    } catch (error) {
      if (error is ApiException && error.unauthorized) {
        _logout(expired: true);
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          // 已有数据时不打断展示, 仅在顶部提示
          _error = describeError(error);
        });
      }
    } finally {
      _refreshing = false;
    }
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

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFF7F1D1D) : null,
    ));
  }

  Future<void> _runRoomAction(
      RoomModel room, Future<void> Function() action) async {
    if (_busyRooms.contains(room.id)) return;
    setState(() => _busyRooms.add(room.id));
    try {
      await action();
      await _refresh();
    } catch (error) {
      _showMessage(describeError(error), error: true);
    } finally {
      if (mounted) setState(() => _busyRooms.remove(room.id));
    }
  }

  /// 手动结束会议: 恢复房间推流后的初始状态, 旧二维码凭证失效
  Future<void> _resetRoom(RoomModel room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.stop_circle_outlined,
            color: Colors.redAccent, size: 32),
        title: Text('结束会议 · ${room.roomCode} 号房间'),
        content: const Text(
            '结束后房间恢复初始状态, 当前客户码/服务码将失效并重新签发, 在线成员会被移出。确定结束吗?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('结束会议'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runRoomAction(room, () async {
      await ApiClient.instance.resetRoom(room.id);
      _showMessage('${room.roomCode} 号房间已结束会议并重新签发凭证');
    });
  }

  /// 摄像头权限开关(默认关闭, 在总览界面按房间开放)
  Future<void> _toggleCamera(RoomModel room) => _runRoomAction(
        room,
        () => ApiClient.instance
            .updateSettings(room.id, cameraEnabled: !room.cameraEnabled),
      );

  Future<void> _logout({bool expired = false}) async {
    if (!mounted || _loggingOut) return;
    if (!expired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('退出登录'),
          content: Text(CastManager.instance.casting
              ? '当前正在统一推流, 退出登录将停止全部房间推流。确定退出吗?'
              : '确定退出当前管理员账号吗?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('退出')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _loggingOut = true;
    ApiClient.instance.logout();
    // 根 ScaffoldMessenger 位于 Navigator 之上, 路由切换后仍可用
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
    if (expired) {
      messenger.showSnackBar(
          const SnackBar(content: Text('登录已失效, 请重新登录')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final runningCount = _rooms.where((room) => room.running).length;
    final onlineCount =
        _rooms.fold<int>(0, (sum, room) => sum + room.onlineMemberCount);
    final alertCount = _rooms.where((room) => room.understaffedAlert).length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('惊喜影视平台 — 房间总览'),
            const SizedBox(width: 14),
            ValueListenableBuilder<bool>(
              valueListenable: _ws.connected,
              builder: (_, connected, __) => _StatusPill(
                color: connected ? Colors.green : Colors.orange,
                label: connected ? '实时已连接' : '实时重连中',
              ),
            ),
          ],
        ),
        actions: [
          if (_rooms.isNotEmpty) ...[
            _StatusPill(
                color: scheme.primary, label: '运行中 $runningCount / ${_rooms.length}'),
            const SizedBox(width: 8),
            _StatusPill(color: Colors.teal, label: '在线 $onlineCount 人'),
            if (alertCount > 0) ...[
              const SizedBox(width: 8),
              _StatusPill(color: Colors.red, label: '红灯 $alertCount'),
            ],
            const SizedBox(width: 12),
          ],
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_error != null && _rooms.isNotEmpty)
            MaterialBanner(
              backgroundColor: scheme.error.withValues(alpha: 0.12),
              leading: Icon(Icons.wifi_off, color: scheme.error),
              content: Text('刷新失败: $_error',
                  style: TextStyle(color: scheme.error, fontSize: 13)),
              actions: [
                TextButton(onPressed: _refresh, child: const Text('重试')),
              ],
            ),
          Expanded(child: _buildBody(scheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rooms.isEmpty) {
      final failed = _error != null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.cloud_off : Icons.meeting_room_outlined,
                size: 56, color: Colors.white24),
            const SizedBox(height: 14),
            Text(failed ? '房间列表加载失败' : '暂无房间',
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
            if (failed) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 224,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        return _RoomCard(
          room: room,
          busy: _busyRooms.contains(room.id),
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
    );
  }
}

class _StatusPill extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final bool busy;
  final int? remainingSeconds;
  final VoidCallback onOpen;
  final VoidCallback onShowQr;
  final VoidCallback onReset;
  final VoidCallback onToggleCamera;

  const _RoomCard({
    required this.room,
    required this.busy,
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

  ({Color color, String label}) get _status {
    if (room.running) return (color: Colors.green, label: '正在运行');
    if (room.closed) return (color: Colors.grey, label: '已关闭');
    if (room.scheduled) return (color: Colors.lightBlue, label: '已预约');
    return (color: Colors.orange, label: '等待就位');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final statusColor = status.color;
    final remaining = remainingSeconds;
    // 倒计时绿色显示, 会议最后 60 秒字体变红
    final countdownColor =
        (remaining != null && remaining <= 60) ? Colors.red : Colors.green;
    final onlineMembers = room.members.where((m) => m.online).toList();
    final alert = room.understaffedAlert;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: alert
              ? Colors.red.withValues(alpha: 0.7)
              : statusColor.withValues(alpha: 0.25),
          width: alert ? 1.5 : 1,
        ),
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
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: statusColor.withValues(alpha: 0.16),
                    ),
                    child: Text(room.roomCode,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: statusColor)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${room.roomCode} 号房间',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (alert)
                    Tooltip(
                      message: '缺人红灯预警: 成员未全部就位',
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.red.shade400),
                      ),
                    ),
                  _StatusPill(color: statusColor, label: status.label),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.people, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      onlineMembers.isEmpty
                          ? '${room.onlineMemberCount}/${room.maxMembers} 就位'
                          : '${room.onlineMemberCount}/${room.maxMembers} 就位 · '
                              '${onlineMembers.map((m) => m.nickname).join('、')}',
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
                      color: room.casting ? scheme.primary : Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      room.castDescription ?? '暂无推流',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: room.casting
                              ? Colors.white
                              : Colors.white54),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    tooltip: room.closed
                        ? '重置房间(重新签发凭证)'
                        : '手动结束会议(恢复初始状态)',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy ? null : onReset,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    color: Colors.redAccent,
                  ),
                  IconButton(
                    tooltip: room.cameraEnabled ? '关闭摄像头权限' : '开放摄像头权限',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy ? null : onToggleCamera,
                    icon: Icon(
                      room.cameraEnabled
                          ? Icons.videocam
                          : Icons.videocam_off_outlined,
                      size: 20,
                    ),
                    color: room.cameraEnabled ? Colors.green : Colors.white38,
                  ),
                  IconButton(
                    tooltip: '二维码获取',
                    visualDensity: VisualDensity.compact,
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code, size: 20),
                  ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    const Icon(Icons.chevron_right,
                        size: 18, color: Colors.white38),
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

  Future<void> _copy(BuildContext context, String label, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label 链接已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final invites = room.invites.where((invite) => !invite.revoked).toList();
    final expireAt = room.inviteExpireAt;
    return AlertDialog(
      title: Text('二维码获取 · ${room.roomCode} 号房间'),
      content: SizedBox(
        width: 560,
        child: invites.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_2, size: 48, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('暂无有效凭证, 请手动结束会议后重新签发',
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < invites.length; i++)
                        _buildInvite(context, invites[i], i),
                    ],
                  ),
                  if (expireAt != null) ...[
                    const SizedBox(height: 12),
                    Text('凭证有效期至 ${expireAt.replaceFirst('T', ' ')}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white38)),
                  ],
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

  Widget _buildInvite(BuildContext context, SeatInviteModel invite, int index) {
    final label = _labelOf(invite, index);
    final url = invite.inviteUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            if (invite.used) ...[
              const SizedBox(width: 6),
              const _StatusPill(color: Colors.green, label: '已使用'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: 210,
          height: 210,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(10),
          child: url != null
              ? QrImageView(data: url, size: 190)
              : const Text('凭证缺少邀请链接',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: url == null ? null : () => _copy(context, label, url),
          icon: const Icon(Icons.copy, size: 16),
          label: Text('复制$label'),
        ),
      ],
    );
  }
}
