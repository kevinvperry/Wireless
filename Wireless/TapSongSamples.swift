import AVFoundation
import Synchronization

/// A bounded hand-off from the real-time HLS tap. The producer only tries a
/// lock and copies into prepared storage; allocation and delivery happen later.
final class TapSongSamples {
    private let lock = NSLock()
    private let enabled = Atomic<Bool>(false)
    private let lostAudio = Atomic<Bool>(false)
    private var pool: [AVAudioPCMBuffer] = []
    private var sparePool: [AVAudioPCMBuffer] = []
    private var head = 0
    private var count = 0
    private var hasAudio = false

    func prepare(format: AVAudioFormat, maximumFrames: UInt32) {
        lock.lock(); defer { lock.unlock() }
        if enabled.load(ordering: .relaxed), hasAudio { lostAudio.store(true, ordering: .relaxed) }
        pool = (0..<16).compactMap { _ in AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames) }
        sparePool = (0..<16).compactMap { _ in AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames) }
        head = 0; count = 0
    }
    func start() {
        lock.lock(); defer { lock.unlock() }
        head = 0; count = 0; hasAudio = false
        lostAudio.store(false, ordering: .relaxed)
        enabled.store(true, ordering: .releasing)
    }
    func stop() {
        enabled.store(false, ordering: .releasing)
        lock.lock(); defer { lock.unlock() }
        count = 0; head = 0
    }
    func offer(_ source: AVAudioPCMBuffer, discontinuity: Bool) {
        guard enabled.load(ordering: .acquiring), source.frameLength > 0 else { return }
        guard lock.try() else { lostAudio.store(true, ordering: .relaxed); return }
        defer { lock.unlock() }
        guard enabled.load(ordering: .acquiring) else { return }
        if discontinuity, hasAudio { lostAudio.store(true, ordering: .relaxed) }
        guard count < pool.count else { lostAudio.store(true, ordering: .relaxed); return }
        let target = pool[(head + count) % pool.count]
        guard source.format == target.format, source.frameLength <= target.frameCapacity else {
            lostAudio.store(true, ordering: .relaxed); return
        }
        target.frameLength = source.frameLength
        let from = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let to = UnsafeMutableAudioBufferListPointer(target.mutableAudioBufferList)
        guard from.count == to.count else { lostAudio.store(true, ordering: .relaxed); return }
        for index in from.indices {
            guard let input = from[index].mData, let output = to[index].mData else { lostAudio.store(true, ordering: .relaxed); return }
            memcpy(output, input, Int(from[index].mDataByteSize))
        }
        hasAudio = true; count += 1
    }
    /// Called off the render thread. Returned buffers own their storage, so the
    /// worker can retain them while the tap immediately reuses its pool slots.
    func drain() -> (buffers: [AVAudioPCMBuffer], discontinuity: Bool) {
        lock.lock()
        guard enabled.load(ordering: .acquiring) else { lock.unlock(); return ([], false) }
        if lostAudio.exchange(false, ordering: .relaxed) { count = 0; lock.unlock(); return ([], true) }
        guard count > 0 else { lock.unlock(); return ([], false) }
        let sources = pool
        let first = head; let available = count
        swap(&pool, &sparePool)
        head = 0; count = 0
        lock.unlock()
        var result: [AVAudioPCMBuffer] = []
        for offset in 0..<available {
            let source = sources[(first + offset) % sources.count]
            guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return ([], true) }
            copy.frameLength = source.frameLength
            let from = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
            let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in from.indices { memcpy(to[index].mData!, from[index].mData!, Int(from[index].mDataByteSize)) }
            result.append(copy)
        }
        return (result, false)
    }
}

/// Monotonic, deterministic policy shared by live-source and fallback capture.
struct SongCaptureHealth {
    enum Action { case continueCapture, fallback, fail }
    private var lastFrames = 0
    private var lastProgress: Double
    private var fallbackUsed: Bool
    init(started: Double, fallbackAlreadyUsed: Bool) {
        lastProgress = started; fallbackUsed = fallbackAlreadyUsed
    }
    mutating func check(frames: Int, now: Double, sourceFailed: Bool) -> Action {
        if frames != lastFrames { lastFrames = frames; lastProgress = now }
        guard sourceFailed || now - lastProgress >= 3 else { return .continueCapture }
        guard !fallbackUsed else { return .fail }
        fallbackUsed = true; lastProgress = now
        return .fallback
    }
}
