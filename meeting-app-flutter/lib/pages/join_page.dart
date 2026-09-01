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

/// 惊喜影视入口页: 填写微信名或QQ名字后扫码入会。
/// 扫码成功后不直接进房, 停留在匹配等待页显示「正在匹配中」,
/// 直到两人都扫码成功才同时进入房间。
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _formKey = GlobalKey<FormState>();
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
    _nicknameController.dispose();
    super.dispose();
  }

  /// 解析邀请深链: meeting://join?roomCode=xxx&token=yyy (兼容 room= 参数)
  ({String roomCode, String token})? _parseInviteLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != AppConfig.inviteScheme) return null;
    final roomCode =
        uri.queryParameters['roomCode'] ?? uri.queryParameters['room'];
    final token = uri.queryParameters['token'];
    if (roomCode == null || token == null) return null;
    return (roomCode: roomCode, token: token);
  }

  Future<void> _openScanner() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        _showError('需要摄像头权限才能扫码入会, 请在系统设置中允许访问相机');
        await openAppSettings();
      } else {
        _showError('需要摄像头权限才能扫码入会');
      }
      return;
    }
    setState(() => _scanning = true);
  }

  /// 从图库选择图片并识别其中的邀请二维码
  Future<void> _pickImageAndScan() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final XFile? image =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    try {
      final capture = await _scannerController.analyzeImage(image.path);
      final barcodes = capture?.barcodes ?? const <Barcode>[];
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw == null) continue;
        final invite = _parseInviteLink(raw);
        if (invite != null) {
          if (mounted) setState(() => _scanning = false);
          await _join(invite.roomCode, invite.token);
          return;
        }
      }
      _showError('图片中未识别到有效的邀请二维码');
    } catch (_) {
      _showError('图片识别失败, 请换一张更清晰的二维码图片');
    }
  }

  /// 扫码成功后入会: 不直接进房, 进入匹配等待页
  Future<void> _join(String roomCode, String inviteToken) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final session = await ApiClient.instance.joinRoom(
        roomCode: roomCode,
        inviteToken: inviteToken,
        nickname: _nicknameController.text.trim(),
        deviceInfo: Platform.operatingSystem,
      );
      if (!mounted) return;
      // 扫码后停留等待: 显示「正在匹配中」, 两人都扫码成功才同时进房
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MatchingPage(session: session)),
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
            if (_joining) return;
            for (final barcode in capture.barcodes) {
              final raw = barcode.rawValue;
              if (raw == null) continue;
              final invite = _parseInviteLink(raw);
              if (invite != null) {
                setState(() => _scanning = false);
                _join(invite.roomCode, invite.token);
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
                      child: const Icon(Icons.movie_outlined,
                          size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text('惊喜影视',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text('填写名字后扫描二维码, 匹配成功即可入场',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white60)),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nicknameController,
                      maxLength: 16,
                      decoration: const InputDecoration(
                          labelText: '微信名或QQ名字',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? '请输入微信名或QQ名字'
                              : null,
                    ),
                    const SizedBox(height: 12),
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

/// 匹配等待页: 扫码成功后停留在此页显示「正在匹配中」,
/// 直到两人都扫码成功(全部成员就位)才同时进入房间。
class MatchingPage extends StatefulWidget {
  final JoinSession session;

  const MatchingPage({super.key, required this.session});

  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  final RoomWsService _ws = RoomWsService();
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  bool _entering = false;
  String? _failedReason;

  @override
  void initState() {
    super.initState();
    _ws.connect(widget.session.roomCode, widget.session.identity,
        widget.session.memberToken, _onRoomEvent);
    // WS 断开时的兜底轮询 + 心跳保持在线(等待期间不下线)
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkMatched());
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _heartbeat());
    _checkMatched();
  }

  void _onRoomEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'MEMBER_JOINED':
      case 'ROOM_ACTIVATED':
      case 'ROOM_RUNNING':
        _checkMatched();
        break;
      case 'ROOM_CLOSED':
      case 'ROOM_RESET':
        if (mounted) setState(() => _failedReason = '房间已结束, 请重新获取二维码');
        break;
      case 'MEMBER_KICKED':
        final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
        if (data['identity'] == widget.session.identity && mounted) {
          setState(() => _failedReason = '您已被移出房间');
        }
        break;
    }
  }

  Future<void> _heartbeat() async {
    try {
      await ApiClient.instance.heartbeat(widget.session.roomCode,
          widget.session.identity, widget.session.memberToken);
    } catch (_) {}
  }

  /// 两人都扫码成功(全部成员就位)后同时进入房间
  Future<void> _checkMatched() async {
    if (_entering || _failedReason != null) return;
    _entering = true;
    try {
      final state =
          await ApiClient.instance.getRoomState(widget.session.roomCode);
      if (!mounted) return;
      if (state.closed) {
        setState(() => _failedReason = '房间已结束, 请重新获取二维码');
        return;
      }
      if (state.allSeated) {
        _pollTimer?.cancel();
        _heartbeatTimer?.cancel();
        _ws.disconnect();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RoomPage(session: widget.session)),
        );
        return;
      }
    } catch (_) {
    } finally {
      _entering = false;
    }
  }

  Future<void> _cancel() async {
    try {
      await ApiClient.instance.leaveRoom(widget.session.roomCode,
          widget.session.identity, widget.session.memberToken);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
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
            if (_failedReason == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('正在匹配中',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('${widget.session.roomCode} 号房间 · 等待另一位扫码入场',
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ] else ...[
              const Icon(Icons.block, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(_failedReason!),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _failedReason == null
                  ? _cancel
                  : () => Navigator.of(context).pop(),
              child: Text(_failedReason == null ? '取消匹配' : '返回'),
            ),
          ],
        ),
      ),
    );
  }
}
