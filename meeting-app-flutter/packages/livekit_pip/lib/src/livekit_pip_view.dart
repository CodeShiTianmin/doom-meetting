import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

/// Place once in the call page widget tree.
///
/// iOS: hosts the native AVSampleBufferDisplayLayer platform view.
/// Android: zero-size no-op (no layout impact).
class LiveKitPipView extends StatelessWidget {
  /// Creates a [LiveKitPipView] attached to [room].
  const LiveKitPipView({required this.room, super.key});

  /// The LiveKit room this PiP view is associated with.
  final Room room;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: 'livekit_pip_view',
        layoutDirection: TextDirection.ltr,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
      );
    }
    return const SizedBox.shrink();
  }
}
