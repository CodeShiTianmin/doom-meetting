import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

/// Configuration for the Android PiP window.
class AndroidPipConfiguration {
  /// Creates Android PiP configuration.
  const AndroidPipConfiguration({
    required this.pipWidgetBuilder,
    this.autoEnterOnBackground = true,
  });

  /// Widget rendered inside the PiP window on Android.
  final Widget Function(BuildContext context, Room room) pipWidgetBuilder;

  /// If true, PiP is entered automatically when the user presses home.
  final bool autoEnterOnBackground;
}

/// Configuration for the iOS PiP window.
class IosPipConfiguration {
  /// Creates iOS PiP configuration.
  const IosPipConfiguration({
    this.includeLocalParticipantVideo = true,
    this.autoEnterOnBackground = true,
  });

  /// If true, the local camera feed is composited as a self-view inset.
  final bool includeLocalParticipantVideo;

  /// If true, PiP is entered automatically when the app is backgrounded.
  final bool autoEnterOnBackground;
}

/// Master configuration for livekit_pip.
class LiveKitPipConfiguration {
  /// Creates the master PiP configuration.
  const LiveKitPipConfiguration({
    required this.android,
    required this.ios,
    this.enabled = true,
    this.disableWhenScreenSharing = true,
  });

  /// Master switch. When false, all PiP functionality is a no-op.
  final bool enabled;

  /// Suppress auto-enter when the local participant is screen sharing.
  final bool disableWhenScreenSharing;

  /// Android-specific configuration.
  final AndroidPipConfiguration android;

  /// iOS-specific configuration.
  final IosPipConfiguration ios;
}
