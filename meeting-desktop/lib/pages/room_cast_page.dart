import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/cast_session.dart';
import '../services/room_video_player.dart';

/// 单房推流界面(正式版):
/// 显示房号 / 推流内容(视频完整文件名) / 成员信息 / 会议倒计时,
/// 提供选择视频文件、开始/停止推流、播放控制(暂停/播放/进度条)、返回总览按钮。
/// 本房间已设置视频文件时, 进入页面或选择文件后直接开始推流(视频暂停在 0 秒),
/// 推流中不再显示选择文件/开始推流按钮; 文件不存在时弹窗提示并保留按钮。
/// 每个房间独立推流、独立控制, 由 PC 端或本房间手机端控制播放。
class RoomCastPage extends StatefulWidget {
  final int roomId;

  const RoomCastPage({super.key, required this.roomId});

  static const List<String> videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'ts',
  ];

  @override
  State<RoomCastPage> createState() => _RoomCastPageState();
}

class _RoomCastPageState extends State<RoomCastPage> {
  RoomModel? _room;
  String? _loadError;
  bool _busy = false;
  Timer? _refreshTimer;
  Timer? _tickTimer;
  double? _seekPreview;
  DateTime _lastRefreshAt = DateTime.now();

  /// 进入页面后仅自动推流一次, 周期刷新不重复触发
  bool _autoStartAttempted = false;

  @override
  void initState() {
    super.initState();
    _refreshRoom();
    CastManager.instance.addListener(_onCastChanged);
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _refreshRoom());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_room?.running ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    CastManager.instance.removeListener(_onCastChanged);
    super.dispose();
  }

  void _onCastChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshRoom() async {
    try {
      final room = await ApiClient.instance.getRoom(widget.roomId);
      if (mounted) {
        setState(() {
          _room = room;
          _loadError = null;
          _lastRefreshAt = DateTime.now();
        });
      }
      // 房间在服务端已退出(会议结束/关闭/重置)时, 本地同步停止推流
      unawaited(CastManager.instance.syncRooms([room]));
      if (!_autoStartAttempted) {
        _autoStartAttempted = true;
        unawaited(_autoStartCast());
      }
    } catch (error) {
      if (mounted && _room == null) {
        setState(() => _loadError = describeError(error));
      }
    }
  }

  int? get _remainingSeconds {
    final base = _room?.remainingSeconds;
    if (base == null) return null;
    final elapsed = DateTime.now().difference(_lastRefreshAt).inSeconds;
    final remaining = base - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  bool get _localCasting => CastManager.instance.isCasting(widget.roomId);

  /// 已设置视频文件且尚未推流时, 进入页面直接开始推流(视频暂停在 0 秒)
  Future<void> _autoStartCast() async {
    if (!mounted || _busy || _localCasting) return;
    if (_room?.closed ?? false) return;
    if (CastManager.instance.videoFileOf(widget.roomId) == null) return;
    await _startCast();
  }

  /// 视频文件不存在时弹窗提示, 文件设置保留, 下方按钮照常显示
  Future<void> _showFileMissingDialog(String path) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.redAccent),
        title: const Text('文件不存在'),
        content: Text('本房间设置的视频文件不存在, 无法推流:\n$path\n\n'
            '请重新选择视频文件。'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  /// 选择本房间视频文件并直接开始推流; 推流中更换文件需先停止当前推流
  Future<void> _pickVideoFile() async {
    if (_busy) return;
    if (_localCasting) {
      final current = CastManager.instance.playerOf(widget.roomId)?.fileName;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          title: const Text('本房间正在推流'),
          content: Text('当前正在推流「${current ?? ''}」。\n'
              '需要先停止当前推流, 才能更换视频文件。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('停止当前推流并继续')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: RoomCastPage.videoExtensions,
      dialogTitle: '选择本房间视频文件(不上传服务器)',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      if (_localCasting) {
        await CastManager.instance.stopVideoCast(widget.roomId);
      }
      CastManager.instance.setVideoFile(widget.roomId, path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _startCast();
  }

  /// 开始本房间推流(仅本房间, 视频暂停在 0 秒); 文件不存在时弹窗提示
  Future<void> _startCast() async {
    if (_busy) return;
    if (_room?.closed ?? false) {
      _showToast('房间已关闭, 请先在总览重置房间', error: true);
      return;
    }
    final path = CastManager.instance.videoFileOf(widget.roomId);
    if (path == null || path.isEmpty) {
      _showToast('请先为本房间选择视频文件', error: true);
      return;
    }
    if (!File(path).existsSync()) {
      await _showFileMissingDialog(path);
      return;
    }
    setState(() => _busy = true);
    try {
      await CastManager.instance.startVideoCast(widget.roomId);
      _showToast('本房间已开始推流(视频暂停在 0 秒), 点击播放按钮开始播放');
    } catch (error) {
      _showToast('推流启动失败: ${describeError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshRoom();
    }
  }

  /// 停止本房间推流: 播放进度归零, 已设置的视频文件保留
  Future<void> _stopCast() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CastManager.instance.stopVideoCast(widget.roomId);
      _showToast('已停止本房间推流, 视频文件保留');
    } catch (error) {
      _showToast('停止推流失败: ${describeError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshRoom();
    }
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFF7F1D1D) : null,
        duration: Duration(seconds: error ? 6 : 3),
      ));
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
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
          title: const Text('单房推流'),
        ),
        body: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off,
                        size: 56, color: Colors.white24),
                    const SizedBox(height: 14),
                    const Text('房间信息加载失败',
                        style:
                            TextStyle(fontSize: 16, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white38)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _refreshRoom,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final manager = CastManager.instance;
    final session = manager.sessionOf(widget.roomId);
    final remaining = _remainingSeconds;
    final countdownColor =
        (remaining != null && remaining <= 60) ? Colors.red : Colors.green;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回总览',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${room.roomCode} 号房间',
                  style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: scheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            if (room.running && remaining != null)
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: countdownColor),
                  const SizedBox(width: 4),
                  Text(_formatClock(remaining),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: countdownColor)),
                ],
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshRoom,
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('返回总览'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 900;
          final sidePanel = _buildSidePanel(room, manager, session, scheme);
          final mainPanel = _buildMainPanel(manager, session, scheme);
          if (narrow) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(height: 360, child: mainPanel),
                const SizedBox(height: 14),
                sidePanel,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: mainPanel,
                ),
              ),
              Container(
                width: 340,
                margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                  color: Colors.white.withValues(alpha: 0.03),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [sidePanel],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 左侧: 推流预览 + 按钮 + 播放控制;
  /// 推流中不显示选择文件/开始推流按钮, 仅保留停止推流与播放控制
  Widget _buildMainPanel(
      CastManager manager, CastSession? session, ColorScheme scheme) {
    // 服务端登记推流中但本机未推流(如重启前遗留)时也提供停止按钮清理登记
    final casting = _localCasting || (_room?.casting ?? false);
    final hasFile = manager.videoFileOf(widget.roomId) != null;
    final player = manager.playerOf(widget.roomId);
    return Column(
      children: [
        Expanded(child: _buildPreview(session, scheme)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!casting)
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickVideoFile,
                icon: const Icon(Icons.video_file_outlined),
                label: Text(hasFile ? '更换视频文件' : '选择视频文件'),
              ),
            if (casting)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _busy ? null : _stopCast,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.stop_circle_outlined),
                label: const Text('停止推流'),
              )
            else
              FilledButton.icon(
                onPressed: (_busy || !hasFile) ? null : _startCast,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cast),
                label: const Text('开始推流'),
              ),
          ],
        ),
        if (casting && player != null) ...[
          const SizedBox(height: 12),
          _buildPlayerControls(player, scheme),
        ],
      ],
    );
  }

  /// 右侧: 推流内容 + 成员信息
  Widget _buildSidePanel(RoomModel room, CastManager manager,
      CastSession? session, ColorScheme scheme) {
    return Column(
      children: [
        _buildCastInfoCard(room, manager, session, scheme),
        const SizedBox(height: 14),
        _buildMembersCard(room, scheme),
      ],
    );
  }

  Widget _buildPreview(CastSession? session, ColorScheme scheme) {
    final track = session?.localVideoTrack;
    final sessionError = session?.error;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: track != null
          ? lk.VideoTrackRenderer(track)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      sessionError != null
                          ? Icons.error_outline
                          : Icons.movie_outlined,
                      size: 56,
                      color: sessionError != null
                          ? scheme.error.withValues(alpha: 0.7)
                          : Colors.white24),
                  const SizedBox(height: 10),
                  Text(
                      sessionError ??
                          '暂无推流 — 选择视频文件后自动开始推流',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: sessionError != null
                              ? scheme.error
                              : Colors.white38,
                          fontSize: 13)),
                ],
              ),
            ),
    );
  }

  /// 播放控制: 暂停/播放 + 进度条(仅作用于本房间播放器)
  Widget _buildPlayerControls(RoomVideoPlayer player, ColorScheme scheme) {
    final durationMs = player.durationMs;
    final positionMs = (_seekPreview ?? player.positionMs.toDouble())
        .clamp(0.0, double.infinity)
        .toDouble();
    final hasDuration = durationMs > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: player.playing ? '暂停(仅本房间)' : '播放(仅本房间)',
            onPressed: () => player.playOrPause(),
            icon: Icon(
                player.playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 36,
                color: scheme.primary),
          ),
          const SizedBox(width: 6),
          Text(_formatClock(positionMs ~/ 1000),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Expanded(
            child: Slider(
              value: hasDuration
                  ? positionMs.clamp(0.0, durationMs.toDouble()).toDouble()
                  : 0,
              max: hasDuration ? durationMs.toDouble() : 1,
              onChanged: hasDuration
                  ? (value) => setState(() => _seekPreview = value)
                  : null,
              onChangeEnd: hasDuration
                  ? (value) {
                      setState(() => _seekPreview = null);
                      player.seek(value.round());
                    }
                  : null,
            ),
          ),
          Text(_formatClock(hasDuration ? durationMs ~/ 1000 : null),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  /// 推流内容: 视频完整文件名(过长换行) + 本房间推流状态
  Widget _buildCastInfoCard(RoomModel room, CastManager manager,
      CastSession? session, ColorScheme scheme) {
    final localCasting = _localCasting;
    final localFileName = manager.videoFileNameOf(widget.roomId);
    final casting = localCasting || room.casting;
    // 推流中显示正在推的文件名(优先服务端登记), 否则显示本机已设置的文件名
    final fileName = casting
        ? (room.castDescription ??
            manager.playerOf(widget.roomId)?.fileName ??
            localFileName)
        : localFileName;
    final String statusText;
    if (localCasting) {
      statusText = '推流中(仅本房间)';
    } else if (room.casting) {
      statusText = '服务端登记为推流中, 本机未推流';
    } else if (localFileName != null) {
      statusText = '已设置视频文件, 尚未推流';
    } else {
      statusText = '未设置视频文件';
    }
    final audioWarning = session?.audioCaptureWarning;
    final sessionError = session?.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(casting ? Icons.cast_connected : Icons.cast,
                    size: 18,
                    color: casting ? scheme.primary : Colors.white38),
                const SizedBox(width: 8),
                Text('推流内容',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: scheme.primary)),
                const Spacer(),
                if (session != null)
                  _SessionBadge(session: session),
              ],
            ),
            const SizedBox(height: 10),
            Text(statusText,
                style: TextStyle(
                    fontSize: 13,
                    color: casting ? Colors.white : Colors.white70)),
            if (fileName != null && fileName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.insert_drive_file_outlined,
                        size: 14, color: Colors.white54),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(fileName,
                        softWrap: true,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: casting ? Colors.white : Colors.white70)),
                  ),
                ],
              ),
            ],
            if (room.casting && !localCasting) ...[
              const SizedBox(height: 8),
              _InlineNotice(
                icon: Icons.info_outline,
                color: Colors.orange,
                text: sessionError ??
                    '本机未在推流该内容(可能为重启前遗留), 请停止后重新推流',
              ),
            ],
            if (audioWarning != null) ...[
              const SizedBox(height: 8),
              _InlineNotice(
                icon: Icons.volume_off_outlined,
                color: Colors.orange,
                text: audioWarning,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 成员信息: 就位人数 + 昵称列表
  Widget _buildMembersCard(RoomModel room, ColorScheme scheme) {
    final members = room.members.where((m) => !m.kicked).toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return (a.seatNo ?? 99).compareTo(b.seatNo ?? 99);
      });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('成员信息 (${room.onlineMemberCount}/${room.maxMembers})',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: scheme.primary)),
                const Spacer(),
                if (room.understaffedAlert)
                  Tooltip(
                    message: '缺人红灯预警',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.red.shade400),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (members.isEmpty)
              const Text('暂无成员, 等待扫码入会',
                  style: TextStyle(fontSize: 12, color: Colors.white38))
            else
              for (final member in members)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 8,
                          color:
                              member.online ? Colors.green : Colors.white24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            member.seatNo != null
                                ? '${member.seatNo}号 · ${member.nickname}'
                                : member.nickname,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (!member.approved)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('待审批',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange)),
                        ),
                      if (member.muted)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.mic_off,
                              size: 14, color: Colors.white38),
                        ),
                      Text(member.online ? '在线' : '离线',
                          style: TextStyle(
                              fontSize: 11,
                              color: member.online
                                  ? Colors.green
                                  : Colors.white38)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  final CastSession session;

  const _SessionBadge({required this.session});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (session.publishing) {
      color = Colors.green;
      label = '推流中';
    } else if (session.connected) {
      color = Colors.lightBlue;
      label = '已连接';
    } else {
      color = Colors.grey;
      label = '未连接';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InlineNotice(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
