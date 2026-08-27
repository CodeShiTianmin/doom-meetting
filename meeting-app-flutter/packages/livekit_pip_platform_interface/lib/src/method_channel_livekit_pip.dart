import 'package:livekit_pip_platform_interface/src/livekit_pip_platform.dart';

/// Default fallback — replaced at runtime by platform-specific registration.
///
/// All methods throw [UnimplementedError]; this class is never used in practice
/// because LivekitPipAndroid or LivekitPipIOS registers itself via
/// dartPluginClass auto-registration.
class MethodChannelLivekitPip extends LivekitPipPlatform {
  /// Creates a [MethodChannelLivekitPip] instance.
  ///
  /// This default fallback is replaced at runtime by the platform-specific
  /// implementation registered via `dartPluginClass` auto-registration.
  MethodChannelLivekitPip();

  @override
  Future<bool> isSupported() => throw UnimplementedError(
    'isSupported() not implemented on this platform.',
  );

  @override
  Future<void> initialize({
    required bool enabled,
    required bool disableWhenScreenSharing,
    required bool androidAutoEnterOnBackground,
    required bool iosAutoEnterOnBackground,
    required bool iosIncludeLocalParticipantVideo,
    required int videoWidth,
    required int videoHeight,
  }) => throw UnimplementedError(
    'initialize() not implemented on this platform.',
  );

  @override
  Future<void> enterPip() => throw UnimplementedError(
    'enterPip() not implemented on this platform.',
  );

  @override
  Future<void> exitPip() => throw UnimplementedError(
    'exitPip() not implemented on this platform.',
  );

  @override
  Future<void> dispose() => throw UnimplementedError(
    'dispose() not implemented on this platform.',
  );

  @override
  Future<void> updateActiveTrack(String trackId) => throw UnimplementedError(
    'updateActiveTrack() not implemented on this platform.',
  );

  @override
  Stream<int> get stateStream => throw UnimplementedError(
    'stateStream not implemented on this platform.',
  );
}
