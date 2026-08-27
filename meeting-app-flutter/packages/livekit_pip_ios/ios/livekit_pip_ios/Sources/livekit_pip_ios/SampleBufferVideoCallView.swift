import AVKit
import UIKit

final class SampleBufferVideoCallView: UIView {

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        layer as! AVSampleBufferDisplayLayer
    }

    var renderingComponent: SampleBufferVideoRendering {
        if #available(iOS 17.0, *) {
            return sampleBufferDisplayLayer.sampleBufferRenderer
        }
        return sampleBufferDisplayLayer
    }

    var videoGravity: AVLayerVideoGravity {
        get { sampleBufferDisplayLayer.videoGravity }
        set { sampleBufferDisplayLayer.videoGravity = newValue }
    }

    var preventsDisplaySleepDuringVideoPlayback: Bool {
        get { sampleBufferDisplayLayer.preventsDisplaySleepDuringVideoPlayback }
        set { sampleBufferDisplayLayer.preventsDisplaySleepDuringVideoPlayback = newValue }
    }
}

protocol SampleBufferVideoRendering {
    @available(iOS 14.0, *)
    var requiresFlushToResumeDecoding: Bool { get }
    var isReadyForMoreMediaData: Bool { get }
    func flush()
    func enqueue(_ sampleBuffer: CMSampleBuffer)
}

extension AVSampleBufferDisplayLayer: SampleBufferVideoRendering {}

@available(iOS 17.0, *)
extension AVSampleBufferVideoRenderer: SampleBufferVideoRendering {}
