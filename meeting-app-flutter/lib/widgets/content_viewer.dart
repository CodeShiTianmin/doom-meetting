import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// 投放文件类型
enum ContentKind { image, video, audio, text, other }

ContentKind detectContentKind(String name, String? mimeType) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.startsWith('image/')) return ContentKind.image;
  if (mime.startsWith('video/')) return ContentKind.video;
  if (mime.startsWith('audio/')) return ContentKind.audio;
  if (mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml') {
    return ContentKind.text;
  }
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  const imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'};
  const videoExts = {'mp4', 'mkv', 'mov', 'webm', 'avi', 'm4v', '3gp', 'ts'};
  const audioExts = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma'};
  const textExts = {
    'txt', 'md', 'log', 'json', 'csv', 'xml', 'yaml', 'yml', 'ini', 'conf'
  };
  if (imageExts.contains(ext)) return ContentKind.image;
  if (videoExts.contains(ext)) return ContentKind.video;
  if (audioExts.contains(ext)) return ContentKind.audio;
  if (textExts.contains(ext)) return ContentKind.text;
  return ContentKind.other;
}

/// 投放文件直接展示:
/// - 图片: 内联展示, 支持双指缩放
/// - 视频/音频: 内置播放器直接播放, 跟随房间共享播放状态(播放/暂停/进度)
/// - 文本: 拉取内容内联展示
/// - 其他(PDF/Office 等): 文件卡片 + 用系统应用打开
class ContentViewer extends StatefulWidget {
  final String url;
  final String name;
  final String? mimeType;
  final bool playing;
  final double positionSeconds;

  const ContentViewer({
    super.key,
    required this.url,
    required this.name,
    this.mimeType,
    required this.playing,
    required this.positionSeconds,
  });

  @override
  State<ContentViewer> createState() => _ContentViewerState();
}

class _ContentViewerState extends State<ContentViewer> {
  late final ContentKind _kind =
      detectContentKind(widget.name, widget.mimeType);
  // 签名地址随状态刷新轮换, 固定使用首个地址避免播放器/图片反复重载
  late final String _url = widget.url;

  VideoPlayerController? _player;
  String? _textContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_kind == ContentKind.video || _kind == ContentKind.audio) {
      _initPlayer();
    } else if (_kind == ContentKind.text) {
      _loadText();
    }
  }

  Future<void> _initPlayer() async {
    final player = VideoPlayerController.networkUrl(Uri.parse(_url));
    _player = player;
    try {
      await player.initialize();
      if (!mounted) return;
      if (widget.positionSeconds > 1) {
        await player
            .seekTo(Duration(milliseconds: (widget.positionSeconds * 1000).round()));
      }
      if (widget.playing) {
        await player.play();
      }
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '播放失败: $error');
    }
  }

  Future<void> _loadText() async {
    try {
      final response = await Dio().get<String>(
        _url,
        options: Options(responseType: ResponseType.plain),
      );
      if (!mounted) return;
      final body = response.data ?? '';
      setState(() => _textContent =
          body.length > 20000 ? '${body.substring(0, 20000)}\n…(内容过长, 已截断)' : body);
    } catch (error) {
      if (mounted) setState(() => _error = '文件加载失败: $error');
    }
  }

  @override
  void didUpdateWidget(covariant ContentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    if (widget.playing != player.value.isPlaying) {
      widget.playing ? player.play() : player.pause();
    }
    final current = player.value.position.inMilliseconds / 1000.0;
    if ((current - widget.positionSeconds).abs() > 3) {
      player.seekTo(
          Duration(milliseconds: (widget.positionSeconds * 1000).round()));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF05071C),
      alignment: Alignment.center,
      child: _error != null ? _buildError() : _buildBody(),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.orange),
          const SizedBox(height: 8),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('用其他应用打开'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_kind) {
      case ContentKind.image:
        return InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            _url,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error, stack) =>
                _fileCard(subtitle: '图片加载失败, 可用其他应用打开'),
          ),
        );
      case ContentKind.video:
        final player = _player;
        if (player == null || !player.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: AspectRatio(
            aspectRatio: player.value.aspectRatio == 0
                ? 16 / 9
                : player.value.aspectRatio,
            child: VideoPlayer(player),
          ),
        );
      case ContentKind.audio:
        return _fileCard(
          icon: Icons.audiotrack,
          subtitle: _player?.value.isInitialized == true
              ? (widget.playing ? '音频播放中' : '音频已就绪, 等待播放')
              : '音频加载中…',
          showOpen: false,
        );
      case ContentKind.text:
        if (_textContent == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 96, 16, 140),
            child: SelectableText(
              _textContent!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ),
        );
      case ContentKind.other:
        return _fileCard(subtitle: '此类型暂不支持内联预览, 可用系统应用打开查看');
    }
  }

  Widget _fileCard(
      {IconData icon = Icons.insert_drive_file,
      required String subtitle,
      bool showOpen = true}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF5B8DEF).withValues(alpha: 0.15),
            ),
            child: Icon(icon, size: 44, color: const Color(0xFF5B8DEF)),
          ),
          const SizedBox(height: 14),
          Text(widget.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (showOpen) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('用系统应用打开'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openExternally() async {
    await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
  }
}
