import Foundation

/// Requires sustained extra lag before changing playback. Brief network bursts
/// should not make the listener hear repeated jumps.
struct DelayCorrectionController {
    private(set) var filteredDelay: Double?
    private var outOfRangeSince: Double?
    private var lastCorrectionAt = -Double.infinity

    mutating func reset() {
        filteredDelay = nil
        outOfRangeSince = nil
    }

    mutating func observe(measured: Double, target: Double, now: Double) -> Bool {
        guard measured.isFinite, measured >= 0 else {
            reset()
            return false
        }

        // At 10 samples per second, this removes ordinary packet-arrival jitter
        // without hiding a change that persists for several seconds.
        let filtered = filteredDelay.map { $0 * 0.8 + measured * 0.2 } ?? measured
        filteredDelay = filtered
        let error = filtered - max(0.25, target)

        // Only correct accumulated playback lag. A shrinking source buffer can
        // make this measurement fall below target without putting the listener
        // ahead of the televised event; an automatic pause could make it worse.
        guard error >= 0.5 else {
            outOfRangeSince = nil
            return false
        }
        if outOfRangeSince == nil { outOfRangeSince = now }
        guard let since = outOfRangeSince,
              now - since >= 2,
              now - lastCorrectionAt >= 3 else { return false }

        lastCorrectionAt = now
        reset()
        return true
    }
}
