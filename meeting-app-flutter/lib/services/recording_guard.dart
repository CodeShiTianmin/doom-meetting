import 'dart:async';

import 'package:flutter/services.dart';

/// 防录制守卫: 允许截屏, 禁止录制
///
/// 通过 MethodChannel 与原生层协作:
/// - Android 14+: Activity.registerScreenCaptureCallback + MediaProjection 检测
/// - Android 全版本: WindowManager FLAG 不设置 FLAG_SECURE(允许截屏),
///   录屏检测由原生层轮询 MediaProjection / 虚拟显示器实现
/// - iOS: UIScreen.capturedDidChangeNotification (isCaptured)
///
/// 检测到录制时回调 onDetected, 由页面执行遮挡 + 上报后端
class RecordingGuard {
  static const MethodChannel _channel =
      MethodChannel('com.doommeeting/recording_guard');

  StreamSubscription<dynamic>? _subscription;
  static const EventChannel _events =
      EventChannel('com.doommeeting/recording_events');

  Future<void> start(void Function(String detail) onDetected) async {
    try {
      await _channel.invokeMethod<void>('startGuard');
    } on MissingPluginException {
      // 原生层未实现时降级为无原生检测
    } on PlatformException {
      // 忽略原生启动失败, 保留水印与上报兜底
    }
    _subscription = _events.receiveBroadcastStream().listen((event) {
      onDetected(event?.toString() ?? '检测到系统级录屏行为');
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel.invokeMethod<void>('stopGuard');
    } catch (_) {}
  }
}
