/// 全局配置: 后端地址通过 --dart-define 注入, 便于多环境打包
class AppConfig {
  AppConfig._();

  /// 后端 HTTP 基地址, 例: https://meeting.example.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// STOMP WebSocket 地址, 例: wss://meeting.example.com/ws
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://10.0.2.2:8080/ws',
  );

  /// PC 隐藏推流身份前缀(与后端 LiveKitTokenService 保持一致)
  static const String castIdentityPrefix = 'pc-publisher-';

  /// 邀请二维码深链协议, 例: meeting://join?roomCode=xxx&token=yyy
  static const String inviteScheme = 'meeting';

  /// 当前 App 版本号(与 android versionCode 保持一致, 用于版本检查)
  static const int versionCode =
      int.fromEnvironment('APP_VERSION_CODE', defaultValue: 1);

  static const Duration heartbeatInterval = Duration(seconds: 10);
  static const Duration stateRefreshInterval = Duration(seconds: 15);
}
