import CoreVideo
import Foundation

/// Prosty, thread-safe ring-buffer na CVPixelBuffer.
/// • push() – używa wątek odbioru (NDI)
/// • popLatest() – używa wątek UI (CADisplayLink)
final class FrameQueue {
    private let capacity: Int
    private var buffer: [CVPixelBuffer?]
    private var readIdx = 0, writeIdx = 0, count = 0
    private let lock = DispatchSemaphore(value: 1)

    init(capacity: Int = 12) {   // 12 = ~200 ms przy 60 fps
        self.capacity = capacity
        self.buffer   = .init(repeating: nil, count: capacity)
    }

    func push(_ pb: CVPixelBuffer) {
        lock.wait()
        buffer[writeIdx] = pb
        writeIdx = (writeIdx + 1) % capacity
        if count == capacity {            // przepełnienie → drop-tail
            readIdx = (readIdx + 1) % capacity
        } else {
            count += 1
        }
        lock.signal()
    }

    /// pobiera *następną* klatkę; gdy brakuje – zwraca nil
    func popNext() -> CVPixelBuffer? {
        lock.wait()
        guard count > 0 else { lock.signal(); return nil }
        let pb = buffer[readIdx]
        buffer[readIdx] = nil
        readIdx = (readIdx + 1) % capacity
        count -= 1
        lock.signal()
        return pb
    }

    var level: Int { lock.wait(); let c = count; lock.signal(); return c }
}
