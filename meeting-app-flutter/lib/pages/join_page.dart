import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _analyzingImage = false;
  bool _inviteHandled = false;
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
      final releaseNotes = (info['releaseNotes'] as String?)?.trim() ?? '';
      final downloadUrl = (info['apkDownloadUrl'] as String?)?.trim() ?? '';
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (dialogContext) => AlertDialog(
          title: Text('发现新版本 ${info['latestVersionName'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (releaseNotes.isNotEmpty) ...[
                Text(releaseNotes),
                const SizedBox(height: 12),
              ],
              if (downloadUrl.isNotEmpty) ...[
                const Text('下载地址',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 4),
                SelectableText(downloadUrl,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF8AB8FF))),
              ],
              if (force) ...[
                const SizedBox(height: 12),
                const Text('当前版本已停用, 请安装新版本后继续使用',
                    style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
              ],
            ],
          ),
          actions: [
            if (downloadUrl.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: downloadUrl));
                  _showMessage('下载地址已复制');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制地址'),
              ),
            if (!force)
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('稍后再说')),
            if (!force)
              FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
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
    setState(() {
      _inviteHandled = false;
      _scanning = true;
    });
  }

  /// 摄像头连续识别会在同一帧内多次回调, 仅处理首个有效邀请码
  void _onScannerDetect(BarcodeCapture capture) {
    if (_joining || _inviteHandled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final invite = _parseInviteLink(raw);
      if (invite != null) {
        _inviteHandled = true;
        setState(() => _scanning = false);
        _join(invite.roomCode, invite.token);
        return;
      }
    }
  }

  /// 从图库选择图片并识别其中的邀请二维码
  Future<void> _pickImageAndScan() async {
    if (_analyzingImage || _joining) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final XFile? image;
    try {
      image = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      _showError('无法打开图库, 请检查相册访问权限');
      return;
    }
    if (image == null || !mounted) return;
    setState(() => _analyzingImage = true);
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
    } finally {
      if (mounted) setState(() => _analyzingImage = false);
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
      _showError(describeError(error));
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
          _inviteHandled = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF7A1F2B),
      ));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
              onPressed: _analyzingImage ? null : _pickImageAndScan,
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(onDetect: _onScannerDetect),
            ),
            // 取景框与提示, 帮助用户对准二维码
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF5B8DEF), width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('将邀请二维码对准取景框, 识别后自动入会',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
            if (_analyzingImage)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x99000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
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
                      icon: _joining
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.qr_code_scanner),
                      label: Text(_joining ? '正在入会…' : '扫描二维码'),
                      onPressed: _joining ? null : _openScanner,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _analyzingImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_library_outlined),
                      label: Text(
                          _analyzingImage ? '正在识别图片…' : '从图库选图识别二维码'),
                      onPressed:
                          _joining || _analyzingImage ? null : _pickImageAndScan,
                    ),
                    const SizedBox(height: 28),
                    const Text('版本 ${AppConfig.versionCode}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white24, fontSize: 11)),
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
  bool _cancelling = false;
  String? _failedReason;
  int _onlineCount = 1;
  int _maxMembers = 2;

  JoinSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _ws.connect(
        session.roomCode, session.identity, session.memberToken, _onRoomEvent);
    // WS 断开时的兜底轮询 + 心跳保持在线(等待期间不下线)
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkMatched());
    _heartbeatTimer =
        Timer.periodic(AppConfig.heartbeatInterval, (_) => _heartbeat());
    _checkMatched();
  }

  void _onRoomEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = (event['payload'] as Map<String, dynamic>?) ?? const {};
    switch (type) {
      case 'MEMBER_JOINED':
      case 'MEMBER_LEFT':
      case 'ROOM_ACTIVATED':
      case 'ROOM_RUNNING':
        _checkMatched();
        break;
      case 'ROOM_CLOSED':
      case 'ROOM_RESET':
      case 'ROOM_DELETED':
        _fail('房间已结束, 请重新获取二维码');
        break;
      case 'MEMBER_KICKED':
        if (data['identity'] == session.identity) _fail('您已被移出房间');
        break;
      case 'JOIN_REJECTED':
        if (data['identity'] == session.identity) {
          _fail('主持人拒绝了您的入会申请');
        }
        break;
    }
  }

  void _fail(String reason) {
    if (!mounted || _failedReason != null) return;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    setState(() => _failedReason = reason);
  }

  Future<void> _heartbeat() async {
    try {
      await ApiClient.instance
          .heartbeat(session.roomCode, session.identity, session.memberToken);
    } catch (_) {}
  }

  /// 两人都扫码成功(全部成员就位)后同时进入房间
  Future<void> _checkMatched() async {
    if (_entering || _cancelling || _failedReason != null) return;
    _entering = true;
    try {
      final state = await ApiClient.instance.getRoomState(session.roomCode);
      if (!mounted || _cancelling) return;
      if (state.closed) {
        _fail('房间已结束, 请重新获取二维码');
        return;
      }
      if (state.allSeated) {
        _pollTimer?.cancel();
        _heartbeatTimer?.cancel();
        _ws.disconnect();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RoomPage(session: session)),
        );
        return;
      }
      setState(() {
        _onlineCount = state.onlineMemberCount;
        _maxMembers = state.maxMembers;
      });
    } catch (_) {
    } finally {
      _entering = false;
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await ApiClient.instance
          .leaveRoom(session.roomCode, session.identity, session.memberToken);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _failedReason;
    final waitingCount = (_maxMembers - _onlineCount).clamp(0, _maxMembers);
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
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (failed == null) ...[
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 96,
                            height: 96,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          Text('$_onlineCount/$_maxMembers',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('正在匹配中',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        waitingCount > 0
                            ? '${session.roomCode} 号房间 · 还需 $waitingCount 位扫码入场'
                            : '${session.roomCode} 号房间 · 即将进入',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13)),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: _ws.connected,
                      builder: (_, connected, __) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 8,
                              color: connected
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent),
                          const SizedBox(width: 6),
                          Text(connected ? '实时连接正常' : '实时连接中断, 自动轮询中',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.block, size: 56, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(failed,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: failed == null
                        ? (_cancelling ? null : _cancel)
                        : () => Navigator.of(context).pop(),
                    child: Text(failed == null
                        ? (_cancelling ? '正在取消…' : '取消匹配')
                        : '返回'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
