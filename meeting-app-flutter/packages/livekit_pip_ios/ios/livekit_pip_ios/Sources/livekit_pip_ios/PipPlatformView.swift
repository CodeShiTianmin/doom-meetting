import AVFoundation
import AVKit
import Flutter
import UIKit
import WebRTC

// Hosts PipVideoRenderer as its full-frame content view.
// PipAdaptiveWindowSizePolicy updates preferredContentSize when track size changes.
// preferredContentSize must always be > .zero to avoid PGPegasus -1003 crash.
private final class PipVideoCallViewController:
    AVPictureInPictureVideoCallViewController,
    PipViewControlling
{
    private(set) var videoRenderer: PipVideoRenderer

    init() {
        let policy = PipAdaptiveWindowSizePolicy()
        let renderer = PipVideoRenderer(windowSizePolicy: policy)
        videoRenderer = renderer
        super.init(nibName: nil, bundle: nil)
        policy.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        videoRenderer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoRenderer)
        NSLayoutConstraint.activate([
            videoRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoRenderer.topAnchor.constraint(equalTo: view.topAnchor),
            videoRenderer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        preferredContentSize = CGSize(width: 320, height: 180) // 16:9 until first frame
    }
}

// containerView is the AVPictureInPictureController activeVideoCallSourceView.
// Actual rendering happens in PipVideoCallViewController.videoRenderer.
// Never recreate pipController or the display layer mid-call.
class PipPlatformView: NSObject, FlutterPlatformView {

    private let containerView: UIView
    private let pipVC = PipVideoCallViewController()
    private var pipController: AVPictureInPictureController?
    private let trackStateAdapter = TrackStateAdapter()
    private let resolver: NativeTrackResolver

    var onStateChanged: ((Int) -> Void)?

    init(
        frame: CGRect,
        viewId: Int64,
        args: Any?,
        resolver: NativeTrackResolver = FlutterWebRTCTrackResolver()
    ) {
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .clear
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.resolver = resolver
        super.init()

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: containerView,
            contentViewController: pipVC
        )
        pipController = AVPictureInPictureController(contentSource: source)
        pipController?.delegate = self
        // Arm auto-enter at controller creation, not later via configure(): the host
        // configure() call is async, so the first background can fire before it lands —
        // and the first minimize would be silently ignored. configure() still applies
        // the consumer's actual preference afterward.
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true

        // Force the content view controller's view (and its AVSampleBufferDisplayLayer)
        // to load. Until the view is loaded, isPictureInPicturePossible never flips to
        // true and the system never auto-enters on background. This does NOT stream
        // frames (the renderer has a window guard) — it only loads the view hierarchy.
        _ = pipVC.view

        // Stop PiP when the app returns to the foreground so the next minimize
        // starts a fresh session.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pipController?.stopPictureInPicture()
    }

    @objc private func handleAppDidBecomeActive() {
        guard let ctrl = pipController, ctrl.isPictureInPictureActive else { return }
        ctrl.stopPictureInPicture()
    }

    func view() -> UIView { containerView }

    // Auto-enter on background MUST be driven by the system via
    // canStartPictureInPictureAutomaticallyFromInline. Never call
    // startPictureInPicture() from a background notification: by the time
    // UIApplication.didEnterBackgroundNotification fires, the UIScene has already
    // left foregroundActive state, so the call fails with AVKitErrorDomain -1001
    // and that failed attempt races with / disrupts the system's automatic entry.
    // isPictureInPicturePossible becomes true via the activeVideoCallSourceView
    // being in a visible window — no frame priming required (see PipVideoRenderer).
    func configure(autoEnterOnBackground: Bool) {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = autoEnterOnBackground
    }

    func rebindTrack(trackId: String) {
        pipVC.videoRenderer.track = resolver.resolveVideoTrack(trackId: trackId)
        trackStateAdapter.activeTrack = pipVC.videoRenderer.track
    }

    func startPictureInPicture() {
        guard let ctrl = pipController else {
            print("[livekit_pip] startPiP: pipController is nil")
            return
        }
        ctrl.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PipPlatformView: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        onStateChanged?(2) // entering
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        trackStateAdapter.isEnabled = true
        pipVC.videoRenderer.resumeStreaming()
        onStateChanged?(3) // active
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        onStateChanged?(4) // exiting
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        trackStateAdapter.isEnabled = false
        onStateChanged?(1) // inactive
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let ns = error as NSError
        print("[livekit_pip] PiP failed to start: \(ns.domain) \(ns.code) — \(ns.localizedDescription)")
        onStateChanged?(1) // inactive
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
