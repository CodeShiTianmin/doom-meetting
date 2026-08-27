import AVKit
import Combine
import Foundation
import UIKit
import WebRTC

final class PipVideoRenderer: UIView, RTCVideoRenderer {

    // Setting this starts/stops frame streaming without recreating the display layer.
    var track: RTCVideoTrack? {
        didSet {
            guard oldValue !== track else { return }
            prepareForTrackRendering(oldValue)
        }
    }

    var displayLayer: CALayer { contentView.layer }
    var pictureInPictureWindowSizePolicy: PipWindowSizePolicy

    private let bufferPublisher: PassthroughSubject<CMSampleBuffer, Never> = .init()

    private lazy var contentView: SampleBufferVideoCallView = {
        let v = SampleBufferVideoCallView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.contentMode = .scaleAspectFill
        v.videoGravity = .resizeAspectFill
        v.preventsDisplaySleepDuringVideoPlayback = true
        return v
    }()

    private var bufferTransformer = BufferTransformer()
    private var bufferUpdatesCancellable: AnyCancellable?

    // Accessed from WebRTC thread AND main thread; written only on WebRTC thread.
    private var contentSize: CGSize = .zero
    private var trackSize: CGSize = .zero {
        didSet {
            guard trackSize != oldValue else { return }
            didUpdateTrackSize()
        }
    }
    private var requiresResize = false {
        didSet { bufferTransformer.requiresResize = requiresResize }
    }
    private var noOfFramesToSkipAfterRendering = 1
    private var skippedFrames = 0
    private var shouldRenderFrame: Bool { skippedFrames == 0 && trackSize != .zero }

    private let resizeRequiredSizeRatioThreshold: CGFloat = 1
    private let sizeRatioThreshold: CGFloat = 15

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    init(windowSizePolicy: PipWindowSizePolicy) {
        pictureInPictureWindowSizePolicy = windowSizePolicy
        super.init(frame: .zero)
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // Called by PipPlatformView delegate when PiP window becomes visible.
    // Flushes any stale pre-PiP frames and re-primes the display layer.
    func resumeStreaming() {
        contentView.renderingComponent.flush()
        noOfFramesToSkipAfterRendering = 0
        skippedFrames = 0
        guard let track else { return }
        track.remove(self)
        track.add(self)
    }

    // MARK: - Window lifecycle (gates frame delivery)

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil {
            startFrameStreaming(for: track, on: newWindow)
        } else {
            stopFrameStreaming(for: track)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentSize = frame.size
    }

    // MARK: - RTCVideoRenderer

    func setSize(_ size: CGSize) { trackSize = size }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        // Apply rotation: iOS encodes landscape with a rotation tag; swap for portrait.
        switch frame.rotation {
        case ._90, ._270:
            trackSize = CGSize(width: CGFloat(frame.height), height: CGFloat(frame.width))
        default:
            trackSize = CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        }
        defer { handleFrameSkippingIfRequired() }
        guard shouldRenderFrame else { return }
        guard let transformed = bufferTransformer.transformAndResizeIfRequired(
            frame, targetSize: contentSize
        ),
        let yuvBuffer = transformed.buffer as? RTCYUVBuffer,
        let sampleBuffer = yuvBuffer.sampleBuffer
        else { return }
        bufferPublisher.send(sampleBuffer)
    }

    // MARK: - Private

    private func process(_ buffer: CMSampleBuffer) {
        guard buffer.isValid else { return }
        if #available(iOS 14.0, *),
           contentView.renderingComponent.requiresFlushToResumeDecoding {
            contentView.renderingComponent.flush()
        }
        if contentView.renderingComponent.isReadyForMoreMediaData {
            contentView.renderingComponent.enqueue(buffer)
        }
    }

    // Window guard: only stream frames while the renderer is in the PiP window.
    // Enqueueing into the AVSampleBufferDisplayLayer before the PiP session owns the
    // layer leaves it in a state where the first system auto-enter fires
    // willStartPiP but never completes (no didStartPiP) — the "first minimize doesn't
    // show, second does" bug. isPictureInPicturePossible becomes true via the
    // activeVideoCallSourceView being in a window, not via frames.
    private func startFrameStreaming(for track: RTCVideoTrack?, on window: UIWindow?) {
        guard window != nil, let track else { return }
        bufferUpdatesCancellable = bufferPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.process($0) }
        track.add(self)
    }

    private func stopFrameStreaming(for track: RTCVideoTrack?) {
        guard bufferUpdatesCancellable != nil else { return }
        bufferUpdatesCancellable?.cancel()
        bufferUpdatesCancellable = nil
        track?.remove(self)
        contentView.renderingComponent.flush()
    }

    private func didUpdateTrackSize() {
        guard contentSize != .zero, trackSize != .zero else { return }
        let wRatio = trackSize.width / contentSize.width
        let hRatio = trackSize.height / contentSize.height
        requiresResize = wRatio >= resizeRequiredSizeRatioThreshold
                      || hRatio >= resizeRequiredSizeRatioThreshold
        let needsSkip = wRatio >= sizeRatioThreshold || hRatio >= sizeRatioThreshold
        noOfFramesToSkipAfterRendering = needsSkip
            ? max(Int(max(Int(wRatio), Int(hRatio)) / 2), 1) : 0
        skippedFrames = 0
        pictureInPictureWindowSizePolicy.trackSize = trackSize
    }

    private func handleFrameSkippingIfRequired() {
        if noOfFramesToSkipAfterRendering > 0 {
            skippedFrames = skippedFrames == noOfFramesToSkipAfterRendering ? 0 : skippedFrames + 1
        } else if skippedFrames > 0 {
            skippedFrames = 0
        }
    }

    private func prepareForTrackRendering(_ oldTrack: RTCVideoTrack?) {
        stopFrameStreaming(for: oldTrack)
        noOfFramesToSkipAfterRendering = 0
        skippedFrames = 0
        requiresResize = false
        startFrameStreaming(for: track, on: window)
    }
}
