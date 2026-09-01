import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../models/room.dart';
import '../services/api_client.dart';
import '../services/cast_manager.dart';
import '../services/cast_session.dart';

/// 单房推流界面(正式版):
/// 显示房号 / 推流内容(视频文件名) / 成员信息 / 会议倒计时,
/// 提供本地视频推流按钮、播放控制(暂停/播放/进度条)、返回总览按钮。
/// 本地视频为统一推流: 本房间发起后, 其它全部房间同步推同一内容,
/// 视频初始暂停, 由 PC 端或手机端控制播放。
class RoomCastPage extends StatefulWidget {
  final int roomId;

  const RoomCastPage({super.key, required this.roomId});

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

  static const _videoExtensions = [
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

  /// 本地视频推流(统一推流): 选择本地视频后全部房间同步推同一内容
  Future<void> _pickLocalVideo() async {
    if (_busy) return;
    if (CastManager.instance.casting) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          title: const Text('正在统一推流'),
          content: Text('当前正在推流「${CastManager.instance.castFileName ?? ''}」。\n'
              '需要先停止当前推流, 才能开始新推流。'),
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
      allowedExtensions: _videoExtensions,
      dialogTitle: '选择本地视频文件(统一推流到全部房间, 不上传服务器)',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted || _busy) return;

    setState(() => _busy = true);
    try {
      if (CastManager.instance.casting) {
        await CastManager.instance.stopUnifiedCast();
      }
      final rooms = await ApiClient.instance.listRooms();
      final failed =
          await CastManager.instance.startUnifiedVideoCast(path, rooms);
      if (failed.isEmpty) {
        _showToast('已开始统一推流(初始暂停), 全部房间同步此内容');
      } else {
        _showToast('统一推流已开始, 以下房间推流失败: ${failed.join('、')}',
            error: true);
      }
    } catch (error) {
      _showToast('统一推流启动失败: ${describeError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshRoom();
    }
  }

  Future<void> _stopCast() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CastManager.instance.stopUnifiedCast();
      _showToast('已停止统一推流');
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

  /// 左侧: 推流预览 + 推流按钮 + 播放控制
  Widget _buildMainPanel(
      CastManager manager, CastSession? session, ColorScheme scheme) {
    return Column(
      children: [
        Expanded(child: _buildPreview(session, scheme)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickLocalVideo,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.video_file_outlined),
              label: Text(manager.casting ? '更换推流视频' : '本地视频推流(全部房间统一)'),
            ),
            if (manager.casting)
              OutlinedButton.icon(
                onPressed: _busy ? null : _stopCast,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止推流'),
              ),
          ],
        ),
        if (manager.casting) ...[
          const SizedBox(height: 12),
          _buildPlayerControls(manager, scheme),
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
                      sessionError ?? '暂无推流 — 点击下方按钮选择本地视频',
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

  /// 播放控制: 暂停/播放 + 进度条(作用于统一共享播放器, 全部房间同步)
  Widget _buildPlayerControls(CastManager manager, ColorScheme scheme) {
    final player = manager.player;
    if (player == null) return const SizedBox.shrink();
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
            tooltip: player.playing ? '暂停(全部房间同步)' : '播放(全部房间同步)',
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

  /// 推流内容: 类型 + 视频文件名 + 本房间推流状态
  Widget _buildCastInfoCard(RoomModel room, CastManager manager,
      CastSession? session, ColorScheme scheme) {
    final fileName = manager.castFileName ?? room.castLabel;
    final casting = manager.casting || room.casting;
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
            Text(
              casting ? '统一视频推流(全部房间同步)' : '暂无推流',
              style: const TextStyle(fontSize: 13),
            ),
            if (casting && fileName != null && fileName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ),
                ],
              ),
            ],
            if (manager.casting && session?.publishing != true) ...[
              const SizedBox(height: 8),
              _InlineNotice(
                icon: Icons.info_outline,
                color: Colors.orange,
                text: sessionError ?? '本房间未加入本次统一推流, 可停止后重新推流',
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
