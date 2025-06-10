import CoreVideo
import Foundation

/// Prosty, thread-safe ring-buffer na CVPixelBuffer.
/// • push() – używa wątek odbioru (NDI)
/// • popLatest() – używa wątek UI (CADisplayLink)
final class FrameQueue {
    private let capacity: Int
    private var buffer: [CVPixelBuffer?]
    private var writeIdx = 0
    private var count = 0
    private let lock = DispatchSemaphore(value: 1)

    init(capacity: Int = 5) {
        self.capacity = capacity
        self.buffer   = .init(repeating: nil, count: capacity)
    }

    /// Wrzuca nową klatkę; nadmiarowe (najstarsze) wyrzuca.
    func push(_ pb: CVPixelBuffer) {
        lock.wait()
        buffer[writeIdx] = pb
        writeIdx = (writeIdx + 1) % capacity
        if count < capacity {
            count += 1
        }
        lock.signal()
    }

    /// Zwraca najnowszą klatkę i czyści bufor (drop-all-older).
    func popLatest() -> CVPixelBuffer? {
        lock.wait()
        guard count > 0 else { lock.signal(); return nil }

        // „cofnij” o 1, żeby dostać ostatnio zapisaną
        writeIdx = (writeIdx - 1 + capacity) % capacity
        let idx  = writeIdx
        let pb   = buffer[idx]
        buffer[idx] = nil
        count = 0                        // starsze niepotrzebne
        lock.signal()
        return pb
    }
}
