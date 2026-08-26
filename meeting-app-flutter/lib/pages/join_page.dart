import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../models/join_session.dart';
import '../services/api_client.dart';
import '../services/ws_service.dart';
import 'room_page.dart';

/// 入会页: 扫描 PC 端二维码或手动输入房号+凭证, 匿名昵称入会
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _formKey = GlobalKey<FormState>();
  final _roomCodeController = TextEditingController();
  final _tokenController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _joining = false;
  bool _scanning = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _checkAppVersion();
  }

  /// APK 私发分发: 启动时检查新版本, 提示下载新 APK
  Future<void> _checkAppVersion() async {
    try {
      final info =
          await ApiClient.instance.checkAppVersion(AppConfig.versionCode);
      if (!mounted || info['updateAvailable'] != true) return;
      final force = info['forceUpdate'] == true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (_) => AlertDialog(
          title: Text('发现新版本 ${info['latestVersionName'] ?? ''}'),
          content: Text(
              '${info['releaseNotes'] ?? ''}\n\n下载地址:\n${info['apkDownloadUrl'] ?? ''}'),
          actions: [
            if (!force)
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('稍后再说')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了')),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _roomCodeController.dispose();
    _tokenController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  /// 解析邀请深链: meeting://join?roomCode=xxx&token=yyy (兼容 room= 参数)
  bool _applyInviteLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != AppConfig.inviteScheme) return false;
    final roomCode =
        uri.queryParameters['roomCode'] ?? uri.queryParameters['room'];
    final token = uri.queryParameters['token'];
    if (roomCode == null || token == null) return false;
    _roomCodeController.text = roomCode;
    _tokenController.text = token;
    return true;
  }

  Future<void> _openScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showError('需要摄像头权限才能扫码入会');
      return;
    }
    setState(() => _scanning = true);
  }

  /// 从图库选择图片并识别其中的邀请二维码
  Future<void> _pickImageAndScan() async {
    final XFile? image =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    try {
      final capture = await _scannerController.analyzeImage(image.path);
      final barcodes = capture?.barcodes ?? const <Barcode>[];
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw != null && _applyInviteLink(raw)) {
          if (mounted) setState(() => _scanning = false);
          _showError('已识别邀请二维码, 请填写昵称后入会');
          return;
        }
      }
      _showError('图片中未识别到有效的邀请二维码');
    } catch (_) {
      _showError('图片识别失败, 请换一张更清晰的二维码图片');
    }
  }

  Future<void> _join() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _joining = true);
    try {
      final session = await ApiClient.instance.joinRoom(
        roomCode: _roomCodeController.text.trim(),
        inviteToken: _tokenController.text.trim(),
        nickname: _nicknameController.text.trim(),
        deviceInfo: Platform.operatingSystem,
      );
      if (!mounted) return;
      if (session.pendingApproval) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WaitingApprovalPage(
              session: session,
              inviteToken: _tokenController.text.trim(),
              nickname: _nicknameController.text.trim(),
            ),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomPage(session: session)),
      );
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('扫码入会'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _scanning = false),
          ),
          actions: [
            IconButton(
              tooltip: '从图库选图识别',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _pickImageAndScan,
            ),
          ],
        ),
        body: MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final raw = barcode.rawValue;
              if (raw != null && _applyInviteLink(raw)) {
                setState(() => _scanning = false);
                return;
              }
            }
          },
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF141B41), Color(0xFF05071C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B8DEF), Color(0xFF8E6BEF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF5B8DEF).withValues(alpha: 0.35),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.connected_tv,
                          size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text('投屏会议',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text('扫描公司提供的二维码, 无需注册即可入会',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white60)),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫描二维码'),
                      onPressed: _joining ? null : _openScanner,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('从图库选图识别二维码'),
                      onPressed: _joining ? null : _pickImageAndScan,
                    ),
                    const SizedBox(height: 20),
                    const Row(children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('或手动输入',
                            style: TextStyle(color: Colors.white38)),
                      ),
                      Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _roomCodeController,
                      decoration: const InputDecoration(
                          labelText: '房号',
                          prefixIcon: Icon(Icons.meeting_room_outlined),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? '请输入房号'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                          labelText: '入会凭证',
                          prefixIcon: Icon(Icons.key_outlined),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? '请输入入会凭证'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nicknameController,
                      maxLength: 16,
                      decoration: const InputDecoration(
                          labelText: '昵称(匿名)',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? '请输入昵称'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _joining ? null : _join,
                      child: _joining
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('进入房间'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 等候室: 等待主持人审批入会, 批准后自动重新入会进房
class WaitingApprovalPage extends StatefulWidget {
  final JoinSession session;
  final String inviteToken;
  final String nickname;

  const WaitingApprovalPage({
    super.key,
    required this.session,
    required this.inviteToken,
    required this.nickname,
  });

  @override
  State<WaitingApprovalPage> createState() => _WaitingApprovalPageState();
}

class _WaitingApprovalPageState extends State<WaitingApprovalPage> {
  final RoomWsService _ws = RoomWsService();
  Timer? _pollTimer;
  bool _entering = false;
  String? _rejectedReason;

  @override
  void initState() {
    super.initState();
    _ws.connect(widget.session.roomCode, widget.session.identity,
        widget.session.memberToken, _onRoomEvent);
    // 兼容 WS 断开时的兼底轮询
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _tryEnter());
  }

  void _onRoomEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    if (data['identity'] != widget.session.identity) return;
    if (type == 'JOIN_APPROVED') {
      _tryEnter();
    } else if (type == 'JOIN_REJECTED') {
      setState(() => _rejectedReason = '主持人拒绝了您的入会申请');
    }
  }

  Future<void> _tryEnter() async {
    if (_entering || _rejectedReason != null) return;
    _entering = true;
    try {
      final session = await ApiClient.instance.joinRoom(
        roomCode: widget.session.roomCode,
        inviteToken: widget.inviteToken,
        nickname: widget.nickname,
        deviceInfo: Platform.operatingSystem,
      );
      if (!mounted) return;
      if (!session.pendingApproval) {
        _pollTimer?.cancel();
        _ws.disconnect();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RoomPage(session: session)),
        );
        return;
      }
    } catch (_) {
    } finally {
      _entering = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_rejectedReason == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('已提交入会申请, 等待主持人审批…'),
            ] else ...[
              const Icon(Icons.block, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(_rejectedReason!),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const JoinPage())),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
