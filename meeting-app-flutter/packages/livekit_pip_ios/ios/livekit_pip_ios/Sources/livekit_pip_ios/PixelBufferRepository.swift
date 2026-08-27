import CoreVideo
import Foundation

final class PixelBufferRepository {

    private struct PoolKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: OSType

        init(_ size: CGSize, pixelFormat: OSType) {
            width = Int(size.width)
            height = Int(size.height)
            self.pixelFormat = pixelFormat
        }
    }

    private var pools: [PoolKey: PixelBufferPool] = [:]
    private let queue = UnfairQueue()

    func dequeuePixelBuffer(
        of size: CGSize,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA
    ) throws -> CVPixelBuffer {
        let key = PoolKey(size, pixelFormat: pixelFormat)
        return try queue.sync {
            let pool: PixelBufferPool
            if let existing = pools[key] {
                pool = existing
            } else {
                pool = PixelBufferPool(bufferSize: size, pixelFormat: pixelFormat)
                pools[key] = pool
            }
            return try pool.dequeuePixelBuffer()
        }
    }
}

final class UnfairQueue {
    private let lock: os_unfair_lock_t

    init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit { lock.deallocate() }

    func sync<T>(_ block: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try block()
    }
}
