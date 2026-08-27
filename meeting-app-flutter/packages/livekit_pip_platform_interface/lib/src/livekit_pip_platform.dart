import 'package:livekit_pip_platform_interface/src/method_channel_livekit_pip.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that implementations of livekit_pip must implement.
///
/// Platform implementations should extend this class rather than implement it.
abstract class LivekitPipPlatform extends PlatformInterface {
  /// Creates a [LivekitPipPlatform] instance.
  ///
  /// Platform implementations must call this constructor with the [_token]
  /// to allow [PlatformInterface.verify] to guard against fake implementations.
  LivekitPipPlatform() : super(token: _token);

  static final Object _token = Object();

  static LivekitPipPlatform _instance = MethodChannelLivekitPip();

  /// The default instance of [LivekitPipPlatform] to use.
  static LivekitPipPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own class.
  static set instance(LivekitPipPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns true if PiP is supported on the current device and OS version.
  Future<bool> isSupported();

  /// Initializes the native PiP infrastructure with the given configuration.
  Future<void> initialize({
    required bool enabled,
    required bool disableWhenScreenSharing,
    required bool androidAutoEnterOnBackground,
    required bool iosAutoEnterOnBackground,
    required bool iosIncludeLocalParticipantVideo,
    required int videoWidth,
    required int videoHeight,
  });

  /// Requests the OS to enter PiP mode.
  Future<void> enterPip();

  /// Requests the OS to exit PiP mode and restore full-screen.
  Future<void> exitPip();

  /// Releases all native resources.
  Future<void> dispose();

  /// Called when the dominant speaker's video track ID changes.
  Future<void> updateActiveTrack(String trackId);

  /// Called when the dominant video's aspect ratio changes.
  ///
  /// Used on Android to size the PiP window. Default is a no-op; iOS derives
  /// its aspect ratio from native frames and does not override this.
  Future<void> updateAspectRatio(int width, int height) async {}

  /// Stream of raw PipState int values (matching PipState enum ordinals).
  ///
  /// Emit order: 0=unsupported, 1=inactive, 2=entering, 3=active, 4=exiting.
  Stream<int> get stateStream;
}
