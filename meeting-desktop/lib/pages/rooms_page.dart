import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/qr_clipboard.dart';
import '../services/ws_service.dart';
import 'login_page.dart';
import 'room_cast_page.dart';

/// 房间总览(固定 1-24 号房):
/// 每张房卡显示房号/人员名称/点赞/房间状态(未使用显示绿色空闲)/
/// 会议倒计时(绿色, 最后 60 秒变红)/推流视频完整文件名(过长换行),
/// 外置操作按钮: 手动结束会议(重置) / 摄像头权限(默认关闭) / 会议时长 / 二维码获取。
/// 会议时长按房间设置(默认 50 分钟), 顶栏可统一设置全部房间时长。
/// 顶栏「统一设置视频文件」批量设置各房间的推流文件并直接开始推流(视频暂停在 0 秒),
/// 各房间手机端随即可看到画面。
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

  /// 刷新进行中收到新事件时标记, 刷新结束后立即再刷一次, 避免漏掉成员进出变化
  bool _refreshPending = false;
  bool _loggingOut = false;
  String? _error;
  Timer? _refreshTimer;
  Timer? _tickTimer;

  /// 正在执行操作的房间 id, 防止重复点击
  final Set<int> _busyRooms = {};

  /// 最近一次刷新到的剩余秒数, 由本地秒级递减驱动倒计时显示
  DateTime _lastRefreshAt = DateTime.now();

  /// 统一推流进度: null 表示未在进行, 否则为已处理房间数
  int? _castAllProgress;
  int _castAllTotal = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    CastManager.instance.addListener(_onCastChanged);
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
    CastManager.instance.removeListener(_onCastChanged);
    CastManager.instance.closeAll();
    super.dispose();
  }

  void _onCastChanged() {
    if (mounted) setState(() {});
  }

  void _onDashboardEvent(Map<String, dynamic> event) {
    // 手机端播放控制指令: 只转发给指令所属房间的播放器执行
    if (event['type'] == 'CAST_CONTROL') {
      final payload = event['payload'];
      final roomCode = event['roomCode'];
      if (payload is Map<String, dynamic> && roomCode is String) {
        final room =
            _rooms.where((room) => room.roomCode == roomCode).firstOrNull;
        if (room != null) {
          CastManager.instance.handleRemoteControl(room.id, payload);
        }
      }
      return;
    }
    // 成员退出/离线先本地置灰, 不等接口刷新
    if (event['type'] == 'MEMBER_LEFT') {
      _applyMemberLeft(event);
    }
    // 红灯预警仅在房卡上以红框 + 警报图标展示, 不弹窗打断操作
    _refresh();
  }

  /// 收到成员退出事件时立即将该成员标为离线(名字变灰), 随后再以接口数据校正
  void _applyMemberLeft(Map<String, dynamic> event) {
    final roomCode = event['roomCode'];
    final payload = event['payload'];
    if (roomCode is! String || payload is! Map<String, dynamic>) return;
    final identity = payload['identity'];
    if (identity is! String) return;
    final index = _rooms.indexWhere((room) => room.roomCode == roomCode);
    if (index < 0) return;
    final room = _rooms[index];
    if (!room.members.any((m) => m.identity == identity && m.online)) return;
    final members = room.members
        .map((m) => m.identity == identity ? m.copyWith(online: false) : m)
        .toList();
    final onlineCount = members.where((m) => m.online && !m.kicked).length;
    if (!mounted) return;
    setState(() {
      _rooms = List.of(_rooms)
        ..[index] =
            room.copyWith(members: members, onlineMemberCount: onlineCount);
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    _refreshing = true;
    try {
      // 总览仅展示系统固定房间(1-24 号房), 后台手动创建的其它房间不在此显示
      final rooms = (await ApiClient.instance.listRooms())
          .where((room) => room.fixed)
          .toList();
      // 固定房号 1-24 按数字排序显示
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
      // 结束会议重置/超时关闭的房间同步停止本地推流(已设置的文件保留)
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
      if (_refreshPending && mounted) {
        _refreshPending = false;
        unawaited(_refresh());
      }
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

  /// 手动结束会议: 旧二维码凭证失效, 房间变为空闲;
  /// 本房间推流停止、状态初始化(视频进度归零), 已设置的视频文件保留
  Future<void> _resetRoom(RoomModel room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.stop_circle_outlined,
            color: Colors.redAccent, size: 32),
        title: Text('结束会议 · ${room.roomCode} 号房间'),
        content: const Text(
            '结束后房间变为空闲, 当前客户码/服务码立即失效并重新签发, 在线成员会被移出;\n'
            '本房间推流停止、状态初始化, 已设置的视频文件保留。确定结束吗?'),
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
      // 先停本地播放进程与捕获轨(进度归零), 服务端重置会一并清除推流登记
      await CastManager.instance.stopVideoCast(room.id, notifyServer: false);
      await ApiClient.instance.resetRoom(room.id);
      _showMessage('${room.roomCode} 号房间已结束会议, 房间空闲, 凭证已重新签发');
    });
  }

  /// 计时复位: 仅将运行中房间的会议计时回到 00:00 重新开始,
  /// 不结束会议, 成员/推流/二维码均不受影响
  Future<void> _resetTimer(RoomModel room) async {
    final elapsed = _elapsedSeconds(room);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt, color: Colors.orange, size: 32),
        title: Text('计时复位 · ${room.roomCode} 号房间'),
        content: Text(
            '会议已进行 ${elapsed == null ? '--' : _RoomCard._formatRemaining(elapsed)}, '
            '复位后从 00:00 重新计时(时长 ${room.durationMinutes ?? '--'} 分钟)。\n'
            '不结束会议, 成员/推流/二维码均不受影响。确定复位吗?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('复位到 00:00'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runRoomAction(room, () async {
      await ApiClient.instance.resetTimer(room.id);
      _showMessage('${room.roomCode} 号房间计时已复位, 从 00:00 重新计时');
    });
  }

  /// 本地推算的已进行秒数(会议时长 - 剩余)
  int? _elapsedSeconds(RoomModel room) {
    final remaining = _remainingSeconds(room);
    final duration = room.durationMinutes;
    if (remaining == null || duration == null) return null;
    final elapsed = duration * 60 - remaining;
    return elapsed > 0 ? elapsed : 0;
  }

  /// 统一设置视频文件: 批量设置各房间的推流文件后逐房直接开始推流
  /// (视频暂停在 0 秒, 手机端随即可看到画面);
  /// 正在推流的房间跳过不改, 文件不存在时弹窗提示不处理
  Future<void> _setVideoFileForAll() async {
    if (_castAllProgress != null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: RoomCastPage.videoExtensions,
      dialogTitle: '选择视频文件(设置到全部房间并开始推流, 不上传服务器)',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    if (!File(path).existsSync()) {
      await _showFileMissingDialog(path);
      return;
    }
    final skipped = CastManager.instance.setVideoFileForRooms(_rooms, path);
    final fileName = CastManager.fileNameOf(path);
    final targets = _rooms
        .where((room) =>
            !room.closed && CastManager.instance.videoFileOf(room.id) == path)
        .toList();
    setState(() {
      _castAllProgress = 0;
      _castAllTotal = targets.length;
    });
    final failed = <String>[];
    try {
      // 逐房启动播放进程并发布, 避免同时拉起大量进程
      for (final room in targets) {
        if (!mounted) return;
        // 已在推流或单房页面正在启动推流的房间跳过
        if (!CastManager.instance.isCasting(room.id) &&
            !CastManager.instance.isTransitioning(room.id)) {
          try {
            await CastManager.instance.startVideoCast(room.id);
          } catch (_) {
            failed.add(room.roomCode);
          }
        }
        if (mounted) setState(() => _castAllProgress = _castAllProgress! + 1);
      }
    } finally {
      if (mounted) setState(() => _castAllProgress = null);
    }
    unawaited(_refresh());
    final notes = <String>[];
    if (skipped.isNotEmpty) notes.add('正在推流未更改: ${skipped.join('、')}');
    if (failed.isNotEmpty) notes.add('推流失败: ${failed.join('、')}');
    if (notes.isEmpty) {
      _showMessage('已为全部房间设置「$fileName」并开始推流(视频暂停在 0 秒)');
    } else {
      _showMessage('已设置「$fileName」并推流; ${notes.join('; ')}',
          error: true);
    }
  }

  /// 视频文件不存在时弹窗提示
  Future<void> _showFileMissingDialog(String path) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.redAccent),
        title: const Text('文件不存在'),
        content: Text('选择的视频文件不存在, 无法设置与推流:\n$path\n\n请重新选择视频文件。'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  /// 摄像头权限开关(默认关闭, 在总览界面按房间开放)
  Future<void> _toggleCamera(RoomModel room) => _runRoomAction(
        room,
        () => ApiClient.instance
            .updateSettings(room.id, cameraEnabled: !room.cameraEnabled),
      );

  /// 会议时长: 服务端按房间保存, 运行中的房间修改后立即按新时长重新计算结束时间
  static const int defaultDurationMinutes = 50;
  static const int minDurationMinutes = 1;
  static const int maxDurationMinutes = 720;

  /// 单房间设置会议时长
  Future<void> _setDuration(RoomModel room) async {
    if (room.closed) {
      _showMessage('房间已关闭, 无法修改会议时长', error: true);
      return;
    }
    final minutes = await _pickDuration(
      title: '会议时长 · ${room.roomCode} 号房间',
      initial: room.durationMinutes ?? defaultDurationMinutes,
      hint: room.running
          ? '房间正在运行, 修改后按新时长从会议开始时间重新计算结束时间。'
          : '下一场会议开始计时后按该时长自动结束。',
    );
    if (minutes == null || !mounted) return;
    await _runRoomAction(room, () async {
      await ApiClient.instance.updateSettings(room.id, durationMinutes: minutes);
      _showMessage('${room.roomCode} 号房间会议时长已设为 $minutes 分钟');
    });
  }

  /// 统一设置全部(未关闭)房间的会议时长
  Future<void> _setDurationForAll() async {
    final minutes = await _pickDuration(
      title: '统一设置会议时长',
      initial: defaultDurationMinutes,
      hint: '应用到全部未关闭房间; 运行中的房间按新时长重新计算结束时间。',
    );
    if (minutes == null || !mounted) return;
    final targets = _rooms.where((room) => !room.closed).toList();
    final failed = <String>[];
    for (final room in targets) {
      try {
        await ApiClient.instance
            .updateSettings(room.id, durationMinutes: minutes);
      } catch (_) {
        failed.add(room.roomCode);
      }
    }
    unawaited(_refresh());
    if (failed.isEmpty) {
      _showMessage('已将 ${targets.length} 个房间的会议时长设为 $minutes 分钟');
    } else {
      _showMessage('会议时长已设为 $minutes 分钟; 失败: ${failed.join('、')}',
          error: true);
    }
  }

  /// 会议时长输入弹窗, 返回 1~720 的分钟数, 取消返回 null
  Future<int?> _pickDuration({
    required String title,
    required int initial,
    required String hint,
  }) {
    final controller = TextEditingController(text: '$initial');
    String? errorText;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            final value = int.tryParse(controller.text.trim());
            if (value == null ||
                value < minDurationMinutes ||
                value > maxDurationMinutes) {
              setDialogState(() => errorText =
                  '请输入 $minDurationMinutes ~ $maxDurationMinutes 之间的整数');
              return;
            }
            Navigator.of(dialogContext).pop(value);
          }

          return AlertDialog(
            icon: const Icon(Icons.timer_outlined, color: Colors.teal, size: 32),
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.white70)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '会议时长(分钟)',
                      suffixText: '分钟',
                      helperText: '默认 $defaultDurationMinutes 分钟, 范围 '
                          '$minDurationMinutes ~ $maxDurationMinutes',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final preset in const [30, 45, 50, 60, 90, 120])
                        ActionChip(
                          label: Text('$preset 分钟'),
                          onPressed: () {
                            controller.text = '$preset';
                            setDialogState(() => errorText = null);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消')),
              FilledButton(onPressed: submit, child: const Text('保存')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout({bool expired = false}) async {
    if (!mounted || _loggingOut) return;
    if (!expired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('退出登录'),
          content: Text(CastManager.instance.anyCasting
              ? '当前有房间正在推流, 退出登录将停止全部房间推流。确定退出吗?'
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
    final idleCount = _rooms.where(_isIdle).length;
    final onlineCount =
        _rooms.fold<int>(0, (sum, room) => sum + room.onlineMemberCount);
    final alertCount = _rooms.where((room) => room.understaffedAlert).length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('漫映网络科技 — 房间总览'),
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
            _StatusPill(color: Colors.green, label: '空闲 $idleCount'),
            const SizedBox(width: 8),
            _StatusPill(color: Colors.teal, label: '在线 $onlineCount 人'),
            if (alertCount > 0) ...[
              const SizedBox(width: 8),
              _StatusPill(color: Colors.red, label: '红灯 $alertCount'),
            ],
            const SizedBox(width: 12),
          ],
          TextButton.icon(
            onPressed: _rooms.isEmpty ? null : _setDurationForAll,
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('统一设置时长'),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _rooms.isEmpty || _castAllProgress != null
                ? null
                : _setVideoFileForAll,
            icon: _castAllProgress != null
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.video_file_outlined, size: 18),
            label: Text(_castAllProgress != null
                ? '统一推流中 $_castAllProgress / $_castAllTotal'
                : '统一设置视频文件'),
          ),
          const SizedBox(width: 4),
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
        mainAxisExtent: 272,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        return _RoomCard(
          room: room,
          busy: _busyRooms.contains(room.id),
          idle: _isIdle(room),
          localFileName: CastManager.instance.videoFileNameOf(room.id),
          localCasting: CastManager.instance.isCasting(room.id),
          remainingSeconds: _remainingSeconds(room),
          elapsedSeconds: _elapsedSeconds(room),
          onOpen: () => Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => RoomCastPage(roomId: room.id)))
              .then((_) => _refresh()),
          onShowQr: () => _showQr(room),
          onReset: () => _resetRoom(room),
          onResetTimer: () => _resetTimer(room),
          onToggleCamera: () => _toggleCamera(room),
          onSetDuration: () => _setDuration(room),
        );
      },
    );
  }
}

/// 空闲: 等待就位且无人在线、未推流的房间(未使用)
bool _isIdle(RoomModel room) =>
    !room.running &&
    !room.closed &&
    !room.scheduled &&
    room.onlineMemberCount == 0 &&
    !room.casting;

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
  final bool idle;

  /// 本机为该房间设置的视频文件名(未设置为空)
  final String? localFileName;

  /// 本机是否正在向该房间推流
  final bool localCasting;
  final int? remainingSeconds;
  final int? elapsedSeconds;
  final VoidCallback onOpen;
  final VoidCallback onShowQr;
  final VoidCallback onReset;
  final VoidCallback onResetTimer;
  final VoidCallback onToggleCamera;
  final VoidCallback onSetDuration;

  const _RoomCard({
    required this.room,
    required this.busy,
    required this.idle,
    required this.localFileName,
    required this.localCasting,
    required this.remainingSeconds,
    required this.elapsedSeconds,
    required this.onOpen,
    required this.onShowQr,
    required this.onReset,
    required this.onResetTimer,
    required this.onToggleCamera,
    required this.onSetDuration,
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
    // 未使用的房间显示绿色空闲; 已有人就位但未满员时提示等待就位
    if (idle) return (color: Colors.green, label: '空闲');
    return (color: Colors.orange, label: '等待就位');
  }

  /// 推流文件行: 推流中显示服务端登记的完整文件名; 未推流但已设置文件时
  /// 显示已设置的文件名(灰色); 否则提示未设置
  ({IconData icon, Color color, String text}) _castLine(ColorScheme scheme) {
    final serverLabel = room.castDescription;
    if (room.casting && serverLabel != null) {
      return (
        icon: Icons.cast_connected,
        color: localCasting ? scheme.primary : Colors.orange,
        text: serverLabel,
      );
    }
    final fileName = localFileName;
    if (fileName != null && fileName.isNotEmpty) {
      return (
        icon: Icons.video_file_outlined,
        color: Colors.white54,
        text: fileName,
      );
    }
    return (icon: Icons.cast, color: Colors.white38, text: '未设置视频文件');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final statusColor = status.color;
    final remaining = remainingSeconds;
    final elapsed = elapsedSeconds;
    // 倒计时绿色显示, 会议最后 60 秒字体变红
    final countdownColor =
        (remaining != null && remaining <= 60) ? Colors.red : Colors.green;
    final members = room.members.where((m) => !m.kicked).toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return (a.seatNo ?? 99).compareTo(b.seatNo ?? 99);
      });
    final castLine = _castLine(scheme);
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
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.warning_amber_rounded,
                            size: 30, color: Colors.red.shade400),
                      ),
                    ),
                  _StatusPill(color: statusColor, label: status.label),
                ],
              ),
              const SizedBox(height: 10),
              // 人员信息: 就位人数 + 每位人员名称(在线绿点/离线灰点)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child:
                        Icon(Icons.people, size: 14, color: Colors.white54),
                  ),
                  const SizedBox(width: 4),
                  Text('${room.onlineMemberCount}/${room.maxMembers} 就位',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: members.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Text('暂无人员',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white38)),
                          )
                        : Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final member in members)
                                _MemberChip(member: member),
                            ],
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
                  if (!room.running && room.durationMinutes != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.timer_outlined,
                        size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text('时长 ${room.durationMinutes} 分钟',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  ],
                  if (room.running && remaining != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.timer_outlined, size: 14, color: countdownColor),
                    const SizedBox(width: 4),
                    Text(_formatRemaining(remaining),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: countdownColor)),
                    if (elapsed != null) ...[
                      const SizedBox(width: 6),
                      Text('已进行 ${_formatRemaining(elapsed)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                    ],
                    const SizedBox(width: 2),
                    // 计时复位: 仅重置会议计时到 00:00, 不结束会议
                    Tooltip(
                      message: '计时复位: 会议计时回到 00:00 重新开始(不结束会议)',
                      child: InkWell(
                        onTap: busy ? null : onResetTimer,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.restart_alt,
                              size: 18,
                              color: busy ? Colors.white24 : Colors.orange),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // 推流视频完整文件名, 过长自动换行
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child:
                          Icon(castLine.icon, size: 13, color: castLine.color),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        castLine.text,
                        softWrap: true,
                        maxLines: 3,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: room.casting
                                ? Colors.white
                                : castLine.color),
                      ),
                    ),
                  ],
                ),
              ),
              // 底部操作栏: 左侧摄像头/二维码, 右侧手动结束会议大按钮
              Row(
                children: [
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
                    tooltip: '会议时长: ${room.durationMinutes ?? '--'} 分钟(点击修改)',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy || room.closed ? null : onSetDuration,
                    icon: const Icon(Icons.timer_outlined, size: 20),
                    color: Colors.teal,
                  ),
                  IconButton(
                    tooltip: '二维码获取',
                    visualDensity: VisualDensity.compact,
                    onPressed: onShowQr,
                    icon: const Icon(Icons.qr_code, size: 20),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    onPressed: busy ? null : onReset,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.stop_circle_outlined, size: 22),
                    label: Text(room.closed ? '重置房间' : '结束会议'),
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

/// 房卡人员名称胶囊: 在线绿点, 离线灰点; 带座位号时显示「1号 张三」
class _MemberChip extends StatelessWidget {
  final MemberModel member;

  const _MemberChip({required this.member});

  @override
  Widget build(BuildContext context) {
    final color = member.online ? Colors.green : Colors.white38;
    final seatNo = member.seatNo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            seatNo != null ? '$seatNo号 ${member.nickname}' : member.nickname,
            style: TextStyle(
                fontSize: 11.5,
                color: member.online ? Colors.white : Colors.white54),
          ),
        ],
      ),
    );
  }
}

/// 单房二维码获取界面:
/// 显示房号, 二维码上方备注「客户码1」「服务码2」, 各配复制按钮(复制二维码图片)。
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

  /// 复制二维码图片到剪贴板(可直接粘贴到微信/QQ 发送);
  /// 不支持图片复制或失败时退回为复制链接文字
  Future<void> _copy(BuildContext context, String label, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final image = await QrClipboard.render(url,
          caption: '$label · ${room.roomCode} 号房间');
      final copied = await QrClipboard.copy(image);
      image.dispose();
      if (copied) {
        message = '$label 二维码图片已复制, 可直接粘贴发送';
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        message = '当前系统不支持复制图片, 已复制 $label 链接';
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      message = '复制二维码图片失败, 已复制 $label 链接';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        Tooltip(
          message: '复制二维码图片到剪贴板',
          child: TextButton.icon(
            onPressed: url == null ? null : () => _copy(context, label, url),
            icon: const Icon(Icons.copy, size: 16),
            label: Text('复制$label'),
          ),
        ),
      ],
    );
  }
}
