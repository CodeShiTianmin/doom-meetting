import AVKit
import Flutter

public class LiveKitPipPlugin: NSObject, FlutterPlugin, LiveKitPipHostApi {

    private var stateEventSink: FlutterEventSink?
    private weak var platformView: PipPlatformView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = LiveKitPipPlugin()
        LiveKitPipHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
        FlutterEventChannel(name: "livekit_pip/state", binaryMessenger: messenger)
            .setStreamHandler(instance)
        registrar.register(
            PipPlatformViewFactory(plugin: instance),
            withId: "livekit_pip_view"
        )
        registrar.publish(instance)
    }

    // MARK: - LiveKitPipHostApi

    func isSupported() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func initialize(request: PipInitRequest) {
        platformView?.configure(autoEnterOnBackground: request.iosAutoEnterOnBackground)
        // Phase 2: wire request.iosIncludeLocalParticipantVideo for self-view inset
    }

    func enterPip() {
        guard let pv = platformView else {
            print("[livekit_pip] enterPip: platformView is nil — view not in tree?")
            return
        }
        pv.startPictureInPicture()
    }

    func exitPip() {
        platformView?.stopPictureInPicture()
    }

    func dispose() {
        platformView?.stopPictureInPicture()
    }

    func updateActiveTrack(trackId: String) {
        platformView?.rebindTrack(trackId: trackId)
    }

    // MARK: - Called by PipPlatformViewFactory

    func didCreatePlatformView(_ view: PipPlatformView) {
        platformView = view
        view.onStateChanged = { [weak self] ordinal in
            self?.stateEventSink?(ordinal)
        }
    }
}

// MARK: - FlutterStreamHandler

extension LiveKitPipPlugin: FlutterStreamHandler {

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        stateEventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stateEventSink = nil
        return nil
    }
}
