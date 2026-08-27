import Accelerate
import CoreVideo
import Foundation
import WebRTC

final class RTCYUVBuffer: NSObject, RTCVideoFrameBuffer {

    private let pixelBufferRepository = PixelBufferRepository()
    private let source: RTCVideoFrameBuffer
    private let conversion: YUVToARGBConversion
    let timeStampNs: Int64

    var width: Int32 { source.width }
    var height: Int32 { source.height }

    // Each RTCYUVBuffer wraps one captured frame and is never reused across frames.
    private lazy var i420ToYUVPixelBuffer = buildI420ToYUVPixelBuffer()

    init(
        source: RTCVideoFrameBuffer,
        conversion: YUVToARGBConversion = .init(),
        timeStampNs: Int64 = 0
    ) {
        self.source = source
        self.conversion = conversion
        self.timeStampNs = timeStampNs
    }

    func toI420() -> any RTCI420BufferProtocol {
        if let i420 = source as? RTCI420Buffer { return i420 }
        return source.toI420()
    }

    func resize(to targetSize: CGSize) -> RTCYUVBuffer? {
        if let i420 = source as? RTCI420Buffer {
            let resized = i420.cropAndScale(
                with: 0, offsetY: 0,
                cropWidth: Int32(source.width), cropHeight: Int32(source.height),
                scaleWidth: Int32(targetSize.width), scaleHeight: Int32(targetSize.height)
            )
            return .init(source: resized, conversion: conversion, timeStampNs: timeStampNs)
        } else if let cvBuffer = source as? RTCCVPixelBuffer,
                  let dequeued = try? pixelBufferRepository.dequeuePixelBuffer(
                      of: targetSize,
                      pixelFormat: CVPixelBufferGetPixelFormatType(cvBuffer.pixelBuffer)
                  ) {
            let count = cvBuffer.bufferSizeForCroppingAndScaling(
                toWidth: Int32(targetSize.width), height: Int32(targetSize.height))
            let tmp: UnsafeMutableRawPointer? = malloc(Int(count))
            cvBuffer.cropAndScale(to: dequeued, withTempBuffer: tmp)
            if let tmp { free(tmp) }
            return .init(source: RTCCVPixelBuffer(pixelBuffer: dequeued), conversion: conversion, timeStampNs: timeStampNs)
        }
        return nil
    }

    var pixelBuffer: CVPixelBuffer? {
        if source is RTCI420Buffer { return i420ToYUVPixelBuffer }
        if let cvBuffer = source as? RTCCVPixelBuffer { return cvBuffer.pixelBuffer }
        return nil
    }

    var sampleBuffer: CMSampleBuffer? {
        guard let pixelBuffer else { return nil }
        let pts = CMTime(value: timeStampNs, timescale: 1_000_000_000)
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        guard let buffer = sampleBuffer else { return nil }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true) as! CFArray
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
        return buffer
    }

    private func buildI420ToYUVPixelBuffer() -> CVPixelBuffer? {
        guard let i420 = source as? RTCI420Buffer,
              let pixelBuffer = try? pixelBufferRepository.dequeuePixelBuffer(
                  of: CGSize(width: Int(width), height: Int(height))
              )
        else { return nil }

        var Yp = vImage_Buffer(
            data: UnsafeMutablePointer(mutating: i420.dataY),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: Int(i420.strideY)
        )
        var Cb = vImage_Buffer(
            data: UnsafeMutablePointer(mutating: i420.dataU),
            height: vImagePixelCount(i420.chromaHeight),
            width: vImagePixelCount(i420.chromaWidth),
            rowBytes: Int(i420.strideU)
        )
        var Cr = vImage_Buffer(
            data: UnsafeMutablePointer(mutating: i420.dataV),
            height: vImagePixelCount(i420.chromaHeight),
            width: vImagePixelCount(i420.chromaWidth),
            rowBytes: Int(i420.strideV)
        )
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        var output = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(pixelBuffer)!,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        let error = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
            &Yp, &Cb, &Cr, &output, &conversion.output,
            [3, 2, 1, 0], 255, vImage_Flags(kvImageNoFlags)
        )
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        return error == kvImageNoError ? pixelBuffer : nil
    }
}
