import CoreVideo
import Foundation

final class PixelBufferPool {

    enum PoolError: LocalizedError {
        case unavailable
        case wouldExceedThreshold
        case unknown(CGSize)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "PixelBufferPool is unavailable"
            case .wouldExceedThreshold: return "PixelBufferPool exhausted — dropping frame"
            case let .unknown(s): return "PixelBufferPool unknown error for size \(s)"
            }
        }
    }

    let maxNoOfBuffers: Int
    let bufferSize: CGSize
    let pixelFormat: OSType

    private var pool: CVPixelBufferPool?

    init(
        bufferSize: CGSize,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        maxNoOfBuffers: Int = 5
    ) {
        self.bufferSize = bufferSize
        self.pixelFormat = pixelFormat
        self.maxNoOfBuffers = maxNoOfBuffers

        var cvPool: CVPixelBufferPool?
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: maxNoOfBuffers
        ]
        let bufAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
            kCVPixelBufferWidthKey as String: Int(bufferSize.width),
            kCVPixelBufferHeightKey as String: Int(bufferSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(nil, poolAttrs as CFDictionary, bufAttrs as CFDictionary, &cvPool)
        pool = cvPool
    }

    func dequeuePixelBuffer() throws -> CVPixelBuffer {
        guard let pool else { throw PoolError.unavailable }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        if status == kCVReturnWouldExceedAllocationThreshold {
            throw PoolError.wouldExceedThreshold
        }
        guard let pixelBuffer else { throw PoolError.unknown(bufferSize) }
        return pixelBuffer
    }
}
