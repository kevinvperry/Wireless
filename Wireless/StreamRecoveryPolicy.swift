import Foundation

/// Retry every published stream, then begin another cycle with capped back-off.
/// Only sustained rendered playback resets the back-off after a weak signal.
struct StreamRecoveryPolicy {
    private(set) var completedCycles = 0
    private var stableSince: Date?

    mutating func reset() {
        completedCycles = 0
        stableSince = nil
    }

    mutating func recordPlayback(at date: Date) {
        if stableSince == nil { stableSince = date }
        if let stableSince, date.timeIntervalSince(stableSince) >= 15 {
            completedCycles = 0
        }
    }

    mutating func nextAttempt(streamCount: Int, currentIndex: Int) -> (index: Int, wait: TimeInterval, cycle: Int) {
        precondition(streamCount > 0)
        stableSince = nil
        if currentIndex + 1 < streamCount {
            return (currentIndex + 1, 1, completedCycles + 1)
        }
        completedCycles = min(completedCycles + 1, 1_000_000)
        let wait = min(15, pow(2, Double(min(completedCycles - 1, 4))))
        return (0, wait, completedCycles + 1)
    }
}
