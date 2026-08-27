import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_pip/src/livekit_pip.dart';
import 'package:livekit_pip/src/pip_state.dart';

/// Wraps the call UI and swaps to the Android PiP widget while in PiP mode.
///
/// On Android, when [LiveKitPip] reports [PipState.entering] or
/// [PipState.active], this renders `AndroidPipConfiguration.pipWidgetBuilder`;
/// otherwise it renders [builder]. On other platforms it always renders
/// [builder] (iOS PiP is rendered natively via `LiveKitPipView`).
class LiveKitPipScaffold extends StatelessWidget {
  /// Creates a scaffold bound to [pip].
  const LiveKitPipScaffold({
    required this.pip,
    required this.builder,
    super.key,
  });

  /// The controller whose state drives the swap.
  final LiveKitPip pip;

  /// Builds the normal, full-screen call UI.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return builder(context);
    }
    return StreamBuilder<PipState>(
      stream: pip.stateStream,
      initialData: PipState.inactive,
      builder: (context, snapshot) {
        final state = snapshot.data ?? PipState.inactive;
        final inPip = state == PipState.entering || state == PipState.active;
        final room = pip.room;
        final pipBuilder = pip.configuration?.android.pipWidgetBuilder;
        if (inPip && room != null && pipBuilder != null) {
          return pipBuilder(context, room);
        }
        return builder(context);
      },
    );
  }
}
