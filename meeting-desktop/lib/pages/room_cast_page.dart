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
      if (mounted) setState(() {});
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
          _lastRefreshAt = DateTime.now();
        });
      }
    } catch (_) {}
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
    if (CastManager.instance.casting) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          title: const Text('正在统一推流'),
          content: Text('当前正在推流「${CastManager.instance.castFileName ?? ''}」。\n'
              '需要先停止当前推流, 才能开始新推流。'),
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
      if (confirmed != true) return;
      await CastManager.instance.stopUnifiedCast();
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _videoExtensions,
      dialogTitle: '选择本地视频文件(统一推流到全部房间, 不上传服务器)',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    List<RoomModel> rooms;
    try {
      rooms = await ApiClient.instance.listRooms();
    } catch (error) {
      _showToast('获取房间列表失败: $error');
      return;
    }
    try {
      final failed =
          await CastManager.instance.startUnifiedVideoCast(path, rooms);
      await _refreshRoom();
      if (failed.isEmpty) {
        _showToast('已开始统一推流(初始暂停), 全部房间同步此内容');
      } else {
        _showToast('统一推流已开始, 以下房间推流失败: ${failed.join('、')}');
      }
    } catch (error) {
      _showToast('统一推流启动失败: $error');
      await _refreshRoom();
    }
  }

  Future<void> _stopCast() async {
    await CastManager.instance.stopUnifiedCast();
    await _refreshRoom();
    _showToast('已停止统一推流');
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
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('返回总览'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧: 推流预览 + 推流按钮 + 播放控制
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(child: _buildPreview(session, scheme)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _pickLocalVideo,
                        icon: const Icon(Icons.video_file_outlined),
                        label: const Text('本地视频推流(全部房间统一)'),
                      ),
                      const SizedBox(width: 12),
                      if (manager.casting)
                        OutlinedButton.icon(
                          onPressed: _stopCast,
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
              ),
            ),
          ),
          // 右侧: 推流内容 + 成员信息
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
              children: [
                _buildCastInfoCard(room, manager, scheme),
                const SizedBox(height: 14),
                _buildMembersCard(room, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(CastSession? session, ColorScheme scheme) {
    final track = session?.localVideoTrack;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: track != null
          ? lk.VideoTrackRenderer(track)
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_outlined, size: 56, color: Colors.white24),
                  SizedBox(height: 10),
                  Text('暂无推流 — 点击下方按钮选择本地视频',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
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
    final positionMs =
        (_seekPreview ?? player.positionMs.toDouble()).clamp(0.0, double.infinity).toDouble();
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
            tooltip: player.playing ? '暂停' : '播放',
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
              value: durationMs > 0
                  ? positionMs.clamp(0.0, durationMs.toDouble()).toDouble()
                  : 0,
              max: durationMs > 0 ? durationMs.toDouble() : 1,
              onChanged: durationMs > 0
                  ? (value) => setState(() => _seekPreview = value)
                  : null,
              onChangeEnd: durationMs > 0
                  ? (value) {
                      _seekPreview = null;
                      player.seek(value.round());
                    }
                  : null,
            ),
          ),
          Text(_formatClock(durationMs ~/ 1000),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  /// 推流内容: 类型 + 视频文件名
  Widget _buildCastInfoCard(
      RoomModel room, CastManager manager, ColorScheme scheme) {
    final fileName = manager.castFileName ?? room.castLabel;
    final casting = manager.casting || room.casting;
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
          ],
        ),
      ),
    );
  }

  /// 成员信息: 就位人数 + 昵称列表
  Widget _buildMembersCard(RoomModel room, ColorScheme scheme) {
    final members = room.members.where((m) => !m.kicked).toList();
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
              ],
            ),
            const SizedBox(height: 10),
            if (members.isEmpty)
              const Text('暂无成员',
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
                        child: Text(member.nickname,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
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
