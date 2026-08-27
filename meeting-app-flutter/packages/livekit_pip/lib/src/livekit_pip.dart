import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_pip/src/active_speaker_selector.dart';
import 'package:livekit_pip/src/aspect_ratio.dart';
import 'package:livekit_pip/src/pip_configuration.dart';
import 'package:livekit_pip/src/pip_state.dart';
import 'package:livekit_pip_platform_interface/livekit_pip_platform_interface.dart';

/// Primary controller for native Picture-in-Picture.
///
/// Create one instance per call session. Call [dispose] when the call ends.
class LiveKitPip {
  final StreamController<PipState> _stateController =
      StreamController<PipState>.broadcast();

  StreamSubscription<int>? _stateSubscription;
  ActiveSpeakerSelector? _speakerSelector;
  EventsListener<RoomEvent>? _roomListener;

  PipState _currentState = PipState.inactive;
  bool _initialized = false;
  bool _disposed = false;
  bool _supported = false;
  LiveKitPipConfiguration? _config;
  Room? _room;

  /// Continuous stream of PiP lifecycle state changes.
  ///
  /// Emits [PipState.unsupported] if the device does not support PiP.
  /// Closed (done event) when [dispose] is called.
  Stream<PipState> get stateStream => _stateController.stream;

  /// The room passed to [initialize], or null before initialize / after dispose.
  Room? get room => _room;

  /// The configuration passed to [initialize], or null before initialize.
  LiveKitPipConfiguration? get configuration => _config;

  /// Returns true if PiP is supported on the current device.
  ///
  /// Safe to call at any time; never throws.
  Future<bool> isSupported() => LivekitPipPlatform.instance.isSupported();

  /// Attaches the plugin to [room] with [config].
  ///
  /// Throws [StateError] if called after [dispose].
  /// Throws [UnsupportedError] if the device does not support PiP.
  Future<void> initialize({
    required Room room,
    required LiveKitPipConfiguration config,
  }) async {
    _assertNotDisposed('initialize');
    _supported = await LivekitPipPlatform.instance.isSupported();
    if (!_supported) {
      _stateController.add(PipState.unsupported);
      throw UnsupportedError(
        'PiP is not supported on this device (isSupported() returned false)',
      );
    }
    _config = config;
    _room = room;
    _speakerSelector = ActiveSpeakerSelector(
      room: room,
      onTrackChanged: (trackId) {
        if (trackId != null && _initialized && !_disposed) {
          unawaited(LivekitPipPlatform.instance.updateActiveTrack(trackId));
        }
      },
      onAspectRatioChanged: (width, height) {
        if (!_initialized || _disposed) return;
        final r = clampPipAspectRatio(width, height);
        if (r.width > 0 && r.height > 0) {
          unawaited(
            LivekitPipPlatform.instance.updateAspectRatio(r.width, r.height),
          );
        }
      },
    );
    _roomListener = room.createListener()
      ..on<RoomDisconnectedEvent>((_) {
        if (!_disposed && _initialized) {
          if (_currentState == PipState.active ||
              _currentState == PipState.entering) {
            unawaited(LivekitPipPlatform.instance.exitPip());
          }
        }
      });
    await LivekitPipPlatform.instance.initialize(
      enabled: config.enabled,
      disableWhenScreenSharing: config.disableWhenScreenSharing,
      androidAutoEnterOnBackground: config.android.autoEnterOnBackground,
      iosAutoEnterOnBackground: config.ios.autoEnterOnBackground,
      iosIncludeLocalParticipantVideo: config.ios.includeLocalParticipantVideo,
      videoWidth: 0,
      videoHeight: 0,
    );
    _stateSubscription = LivekitPipPlatform.instance.stateStream.listen(
      (raw) {
        final state = PipState.values[raw];
        _currentState = state;
        _stateController.add(state);
      },
    );
    _initialized = true;
    // Push initial dominant track — participants may already be publishing
    // video before initialize() is called, so we can't wait for the first
    // ActiveSpeakersChangedEvent.
    final initialTrackId = _speakerSelector?.currentBestTrackId;
    if (initialTrackId != null) {
      unawaited(LivekitPipPlatform.instance.updateActiveTrack(initialTrackId));
    }
    final initialDim = _speakerSelector?.currentBestDimensions;
    if (initialDim != null) {
      final r = clampPipAspectRatio(initialDim.width, initialDim.height);
      if (r.width > 0 && r.height > 0) {
        unawaited(
          LivekitPipPlatform.instance.updateAspectRatio(r.width, r.height),
        );
      }
    }
  }

  /// Requests the OS to enter PiP mode.
  ///
  /// Throws [StateError] if not initialized or already disposed.
  /// Throws [UnsupportedError] if [isSupported] returned false.
  Future<void> enterPiP() {
    _assertInitialized('enterPiP');
    if (!_supported) {
      throw UnsupportedError(
        'PiP is not supported on this device (isSupported() returned false)',
      );
    }
    // Suppress PiP while the local participant is screen-sharing.
    if ((_config?.disableWhenScreenSharing ?? true) &&
        (_speakerSelector?.isScreenSharing ?? false)) {
      return Future<void>.value();
    }
    return LivekitPipPlatform.instance.enterPip();
  }

  /// Requests the OS to exit PiP mode and restore full-screen.
  ///
  /// Throws [StateError] if not initialized or already disposed.
  Future<void> exitPiP() {
    _assertInitialized('exitPiP');
    return LivekitPipPlatform.instance.exitPip();
  }

  /// Releases all native resources and closes [stateStream].
  ///
  /// Idempotent — safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _roomListener?.dispose();
    _roomListener = null;
    await _speakerSelector?.dispose();
    _speakerSelector = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await LivekitPipPlatform.instance.dispose();
    await _stateController.close();
    _config = null;
    _room = null;
    _initialized = false;
  }

  void _assertNotDisposed(String method) {
    if (_disposed) {
      throw StateError('LiveKitPip.$method called after dispose()');
    }
  }

  void _assertInitialized(String method) {
    _assertNotDisposed(method);
    if (!_initialized) {
      throw StateError('LiveKitPip.$method called before initialize()');
    }
  }
}
