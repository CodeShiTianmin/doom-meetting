import Foundation
import WebRTC

struct BufferTransformer {

    var requiresResize = false

    func transformAndResizeIfRequired(
        _ frame: RTCVideoFrame,
        targetSize: CGSize
    ) -> RTCVideoFrame? {
        // Always prefer I420 path (RTCCVPixelBuffer has known rendering issues per template).
        let buffer: RTCVideoFrameBuffer = (frame.buffer as? RTCI420Buffer) ?? frame.buffer
        guard let yuvBuffer = transformBuffer(buffer, targetSize: targetSize, timeStampNs: frame.timeStampNs) else { return nil }
        return RTCVideoFrame(
            buffer: yuvBuffer,
            rotation: frame.rotation,
            timeStampNs: frame.timeStampNs
        )
    }

    private func transformBuffer(
        _ source: RTCVideoFrameBuffer,
        targetSize: CGSize,
        timeStampNs: Int64
    ) -> RTCYUVBuffer? {
        if requiresResize {
            let sourceSize = CGSize(width: CGFloat(source.width), height: CGFloat(source.height))
            return RTCYUVBuffer(source: source, timeStampNs: timeStampNs)
                .resize(to: resizeSize(sourceSize, toFitWithin: targetSize))
        }
        return RTCYUVBuffer(source: source, timeStampNs: timeStampNs)
    }

    private func resizeSize(_ size: CGSize, toFitWithin container: CGSize) -> CGSize {
        let ratio = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }
}
