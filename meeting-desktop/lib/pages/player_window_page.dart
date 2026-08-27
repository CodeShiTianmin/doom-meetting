import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 独立本地视频播放进程(以 `exe player <base64-json>` 参数重启自身):
///
/// 本地视频在此独立进程窗口内解码播放, 主进程对该窗口做窗口捕获推流。
/// 必须是独立进程而不是同进程子窗口 —— WebRTC 的 Windows 窗口枚举会
/// 过滤掉本进程自己的窗口(防 GetWindowText 死锁), 同进程子窗口永远
/// 不会出现在可捕获列表里。
///
/// 与主进程的通信(标准输入/输出, 每行一条 JSON):
/// - stdin 接收指令: {"cmd":"playOrPause"} / {"cmd":"seekMs","value":..} /
///   {"cmd":"audioRoute","keywords":[..]}(把播放声音路由到指定虚拟声卡) /
///   {"cmd":"close"}
/// - stdout 上报: `@@player {"event":"ready"}`(窗口标题已就绪, 可捕获),
///   以及每 500ms 一条 `@@player {"event":"state",...}` 播放状态
/// - 窗口被手动关闭时进程退出, 主进程以进程退出为关闭信号停止对应推流
class PlayerWindowApp extends StatefulWidget {
  final Map<String, dynamic> params;

  const PlayerWindowApp({super.key, required this.params});

  @override
  State<PlayerWindowApp> createState() => _PlayerWindowAppState();
}

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

typedef _EnumWindowsProcC = Int32 Function(IntPtr hwnd, IntPtr lparam);

final int Function(Pointer<NativeFunction<_EnumWindowsProcC>>, int)
    _enumWindows = _user32.lookupFunction<
        Int32 Function(Pointer<NativeFunction<_EnumWindowsProcC>>, IntPtr),
        int Function(
            Pointer<NativeFunction<_EnumWindowsProcC>>, int)>('EnumWindows');

final int Function(int, Pointer<Uint32>) _getWindowThreadProcessId =
    _user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');

final int Function(int) _isWindowVisible = _user32.lookupFunction<
    Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');

final int Function(int, Pointer<Utf16>) _setWindowText = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>),
    int Function(int, Pointer<Utf16>)>('SetWindowTextW');

int _ownWindowHwnd = 0;

int _enumProc(int hwnd, int lparam) {
  final pidPtr = calloc<Uint32>();
  _getWindowThreadProcessId(hwnd, pidPtr);
  final ownerPid = pidPtr.value;
  calloc.free(pidPtr);
  if (ownerPid == pid && _isWindowVisible(hwnd) != 0) {
    _ownWindowHwnd = hwnd;
    return 0;
  }
  return 1;
}

/// 将本进程主窗口标题改为捕获标题, 主进程按该标题枚举窗口做捕获推流
Future<bool> _applyWindowTitle(String title) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    _ownWindowHwnd = 0;
    _enumWindows(Pointer.fromFunction<_EnumWindowsProcC>(_enumProc, 1), 0);
    if (_ownWindowHwnd != 0) {
      final text = title.toNativeUtf16();
      _setWindowText(_ownWindowHwnd, text);
      calloc.free(text);
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

class _PlayerWindowAppState extends State<PlayerWindowApp> {
  late final Player _player;
  late final VideoController _videoController;
  Timer? _stateTimer;
  StreamSubscription<String>? _stdinSub;

  String get _title => widget.params['title'] as String? ?? '投屏播放';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _player.open(Media(widget.params['path'] as String), play: true);

    _stdinSub = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleCommand, onDone: _exit, onError: (_) {});

    unawaited(_setup());
    _stateTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _reportState());
  }

  Future<void> _setup() async {
    await _applyWindowTitle(_title);
    _emit({'event': 'ready'});
  }

  void _handleCommand(String line) {
    Map<String, dynamic> command;
    try {
      command = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (command['cmd']) {
      case 'playOrPause':
        _player.playOrPause();
        break;
      case 'seekMs':
        _player.seek(Duration(milliseconds: command['value'] as int));
        break;
      case 'audioRoute':
        final keywords = (command['keywords'] as List<dynamic>? ?? const [])
            .map((keyword) => keyword.toString().toLowerCase())
            .toList();
        unawaited(_routeAudio(keywords));
        break;
      case 'close':
        unawaited(_exit());
        break;
    }
  }

  /// 把播放器音频输出切到匹配关键字的设备(虚拟声卡输入端),
  /// 使主进程能从虚拟声卡输出端采集到本视频的伴音
  Future<void> _routeAudio(List<String> keywords) async {
    List<AudioDevice> devices = _player.state.audioDevices;
    if (devices.length <= 1) {
      try {
        devices = await _player.stream.audioDevices
            .firstWhere((list) => list.length > 1)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        devices = _player.state.audioDevices;
      }
    }
    AudioDevice? target;
    for (final keyword in keywords) {
      for (final device in devices) {
        final label = '${device.description} ${device.name}'.toLowerCase();
        if (label.contains(keyword)) {
          target = device;
          break;
        }
      }
      if (target != null) break;
    }
    if (target == null) {
      _emit({'event': 'audioRoute', 'ok': false});
      return;
    }
    try {
      await _player.setAudioDevice(target);
      _emit({'event': 'audioRoute', 'ok': true, 'device': target.description});
    } catch (_) {
      _emit({'event': 'audioRoute', 'ok': false});
    }
  }

  void _emit(Map<String, dynamic> message) {
    stdout.writeln('@@player ${jsonEncode(message)}');
  }

  void _reportState() {
    _emit({
      'event': 'state',
      'playing': _player.state.playing,
      'positionMs': _player.state.position.inMilliseconds,
      'durationMs': _player.state.duration.inMilliseconds,
    });
  }

  Future<void> _exit() async {
    _stateTimer?.cancel();
    await _stdinSub?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
    exit(0);
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _stdinSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Video(controller: _videoController, controls: null),
      ),
    );
  }
}
