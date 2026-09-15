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

final int Function(int) _isWindowVisible =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'IsWindowVisible');

final int Function(int, Pointer<Utf16>) _setWindowText = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>),
    int Function(int, Pointer<Utf16>)>('SetWindowTextW');

final int Function(int, int) _getWindowLongPtr = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32),
    int Function(int, int)>('GetWindowLongPtrW');

final int Function(int, int, int) _setWindowLongPtr = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32, IntPtr),
    int Function(int, int, int)>('SetWindowLongPtrW');

final int Function(int, int, int, int, int, int, int) _setWindowPos =
    _user32.lookupFunction<
        Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)>('SetWindowPos');

final int Function(int) _getSystemMetrics =
    _user32.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'GetSystemMetrics');

final int Function(int, int) _monitorFromWindow = _user32.lookupFunction<
    IntPtr Function(IntPtr, Uint32),
    int Function(int, int)>('MonitorFromWindow');

final int Function(int, Pointer<Int32>) _getMonitorInfo =
    _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Int32>),
        int Function(int, Pointer<Int32>)>('GetMonitorInfoW');

const int _gwlStyle = -16;
const int _gwlExStyle = -20;
const int _wsExToolWindow = 0x00000080;
const int _wsExNoActivate = 0x08000000;
const int _hwndBottom = 1;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;
const int _wsCaption = 0x00C00000;
const int _wsThickFrame = 0x00040000;
const int _wsMinimizeBox = 0x00020000;
const int _wsMaximizeBox = 0x00010000;
const int _wsSysMenu = 0x00080000;
const int _swpFrameChangedFlags = 0x0001 | 0x0002 | 0x0004 | 0x0020;
const int _smCxScreen = 0;
const int _smCyScreen = 1;
const int _smXVirtualScreen = 76;
const int _smYVirtualScreen = 77;
const int _smCxVirtualScreen = 78;
const int _smCyVirtualScreen = 79;
const int _monitorDefaultToPrimary = 1;

/// MONITORINFO 结构大小(字节): cbSize + rcMonitor + rcWork + dwFlags
const int _monitorInfoSize = 40;

/// 播放窗口尺寸(即窗口捕获推流的画面尺寸)
const int _playerWindowWidth = 1280;
const int _playerWindowHeight = 720;

/// 后台模式下播放窗口留在屏幕内的边条宽度(px)。
/// 窗口不能整体移出所有显示器: 完全不在任何显示器上的窗口会被 DWM 判定为
/// 被遮挡, Flutter 的 DXGI 交换链 Present 被跳过、画面不再更新, 窗口捕获
/// 只能得到黑屏; 只要有一条边留在屏幕内, DWM 就会持续合成整个窗口,
/// 捕获到的是完整画面(捕获读的是窗口重定向表面, 与是否露出无关)
const int _visibleStripPx = 4;

/// 去掉标题栏/边框: 窗口捕获推流时手机端只看到视频画面,
/// 不出现「投屏播放」标题文字(窗口标题文本仍在, 不影响捕获枚举)
void _removeWindowChrome(int hwnd) {
  final style = _getWindowLongPtr(hwnd, _gwlStyle);
  final newStyle = style &
      ~(_wsCaption |
          _wsThickFrame |
          _wsMinimizeBox |
          _wsMaximizeBox |
          _wsSysMenu);
  _setWindowLongPtr(hwnd, _gwlStyle, newStyle);
  _setWindowPos(hwnd, 0, 0, 0, 0, 0, _swpFrameChangedFlags);
}

/// 窗口所在显示器的矩形(left, top, right, bottom); 取不到时回退主显示器
({int left, int top, int right, int bottom}) _monitorRect(int hwnd) {
  final monitor = _monitorFromWindow(hwnd, _monitorDefaultToPrimary);
  final info = calloc<Int32>(_monitorInfoSize ~/ 4);
  try {
    info[0] = _monitorInfoSize;
    if (monitor != 0 && _getMonitorInfo(monitor, info) != 0) {
      return (left: info[1], top: info[2], right: info[3], bottom: info[4]);
    }
  } finally {
    calloc.free(info);
  }
  return (
    left: 0,
    top: 0,
    right: _getSystemMetrics(_smCxScreen),
    bottom: _getSystemMetrics(_smCyScreen),
  );
}

/// 计算后台播放窗口位置: 沿当前显示器一条没有相邻显示器的边缘挂到屏幕外,
/// 只留 [_visibleStripPx] 宽的边条在屏幕内(见该常量说明)。
/// 四周都有显示器的极端布局下退回屏幕内左上角(仍压在最底层)
({int x, int y}) _backgroundWindowPosition(int hwnd) {
  final monitor = _monitorRect(hwnd);
  final virtualLeft = _getSystemMetrics(_smXVirtualScreen);
  final virtualTop = _getSystemMetrics(_smYVirtualScreen);
  final virtualRight = virtualLeft + _getSystemMetrics(_smCxVirtualScreen);
  final virtualBottom = virtualTop + _getSystemMetrics(_smCyVirtualScreen);
  if (monitor.left <= virtualLeft) {
    return (
      x: monitor.left - _playerWindowWidth + _visibleStripPx,
      y: monitor.top,
    );
  }
  if (monitor.top <= virtualTop) {
    return (
      x: monitor.left,
      y: monitor.top - _playerWindowHeight + _visibleStripPx,
    );
  }
  if (monitor.right >= virtualRight) {
    return (x: monitor.right - _visibleStripPx, y: monitor.top);
  }
  if (monitor.bottom >= virtualBottom) {
    return (x: monitor.left, y: monitor.bottom - _visibleStripPx);
  }
  return (x: monitor.left, y: monitor.top);
}

/// 后台窗口模式(房间推流): 不进任务栏、不抢焦点、压到最底层,
/// 并沿显示器边缘挂到屏幕外(只露一条细边), 推流时不遮挡桌面操作。
/// 窗口保持可见状态(最小化/隐藏/整体移出屏幕的窗口都无法被正常捕获)
void _applyBackgroundMode(int hwnd) {
  final exStyle = _getWindowLongPtr(hwnd, _gwlExStyle);
  _setWindowLongPtr(
      hwnd, _gwlExStyle, exStyle | _wsExToolWindow | _wsExNoActivate);
  final position = _backgroundWindowPosition(hwnd);
  _setWindowPos(hwnd, _hwndBottom, position.x, position.y, _playerWindowWidth,
      _playerWindowHeight, _swpNoActivate | _swpFrameChanged);
}

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
Future<bool> _applyWindowTitle(String title, {bool background = false}) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    _ownWindowHwnd = 0;
    _enumWindows(Pointer.fromFunction<_EnumWindowsProcC>(_enumProc, 1), 0);
    if (_ownWindowHwnd != 0) {
      final text = title.toNativeUtf16();
      _setWindowText(_ownWindowHwnd, text);
      calloc.free(text);
      _removeWindowChrome(_ownWindowHwnd);
      if (background) {
        _applyBackgroundMode(_ownWindowHwnd);
      }
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
  Socket? _controlSocket;
  StreamSubscription<String>? _controlSub;
  bool _exiting = false;

  String get _title => widget.params['title'] as String? ?? '投屏播放';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    // 推流初始暂停, 由 PC 端或本房间手机端控制播放/暂停
    _player.open(Media(widget.params['path'] as String),
        play: widget.params['paused'] != true);

    _stdinSub = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleCommand, onDone: _exit, onError: (_) {});

    unawaited(_setup());
    _stateTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _reportState());
  }

  Future<void> _setup() async {
    await _connectControlChannel();
    if (Platform.isWindows) {
      await _applyWindowTitle(_title,
          background: widget.params['background'] == true);
    }
    _emit({'event': 'ready'});
  }

  /// 控制通道走本地回环 TCP(stdin 管道在部分 Windows 环境下不可靠)
  Future<void> _connectControlChannel() async {
    final port = (widget.params['controlPort'] as num?)?.toInt();
    if (port == null) return;
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      _controlSocket = socket;
      _controlSub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleCommand, onDone: _exit, onError: (_) {});
    } catch (_) {
      // 连接失败时回退 stdin/stdout 通信
    }
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
        final value = (command['value'] as num?)?.toInt();
        if (value != null) {
          _player.seek(Duration(milliseconds: value < 0 ? 0 : value));
        }
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
    final line = '@@player ${jsonEncode(message)}';
    final socket = _controlSocket;
    if (socket != null) {
      try {
        socket.write('$line\n');
      } catch (_) {}
    }
    stdout.writeln(line);
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
    if (_exiting) return;
    _exiting = true;
    _stateTimer?.cancel();
    await _stdinSub?.cancel();
    await _controlSub?.cancel();
    _controlSocket?.destroy();
    try {
      await _player.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    exit(0);
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _stdinSub?.cancel();
    _controlSub?.cancel();
    _controlSocket?.destroy();
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
