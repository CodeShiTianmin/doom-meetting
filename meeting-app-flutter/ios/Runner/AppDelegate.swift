import Flutter
import UIKit

/// 防录制原生支持(iOS): 允许截屏, 禁止录制
/// 通过 UIScreen.capturedDidChangeNotification 检测系统录屏/AirPlay 镜像,
/// 检测到后经 EventChannel 通知 Flutter 层遮挡 + 上报
@main
@objc class AppDelegate: FlutterAppDelegate {

  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController

    let methodChannel = FlutterMethodChannel(
      name: "com.doommeeting/recording_guard",
      binaryMessenger: controller.binaryMessenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startGuard":
        self?.startGuard()
        result(nil)
      case "stopGuard":
        self?.stopGuard()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "com.doommeeting/recording_events",
      binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(self)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startGuard() {
    stopGuard()
    observer = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      if UIScreen.main.isCaptured {
        self?.eventSink?("检测到系统录屏(iOS isCaptured)")
      }
    }
    if UIScreen.main.isCaptured {
      eventSink?("检测到系统录屏(iOS isCaptured)")
    }
  }

  private func stopGuard() {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
