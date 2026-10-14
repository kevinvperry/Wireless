import Combine
import Foundation

// Adapted from Autohop's SleepTimerService. Wireless only needs the fixed-
// duration mode because a continuous radio stream has no reliable episode end.
@MainActor
final class SleepTimerService: ObservableObject {
    @Published private(set) var timeRemaining: TimeInterval = -1

    var isActive: Bool { timeRemaining >= 0 }

    var onFadeVolume: ((Float) -> Void)?
    var onPause: (() -> Void)?

    static let gradualFadeDuration: TimeInterval = 30
    private let autoRestartWindow: TimeInterval = 5 * 60
    private var timer: Timer?
    private var deadline: Date?
    private(set) var firedAt: Date?
    private(set) var lastDuration: TimeInterval?

    func start(seconds: TimeInterval) {
        let duration = max(1, seconds)
        lastDuration = duration
        firedAt = nil
        deadline = Date().addingTimeInterval(duration)
        timeRemaining = duration
        onFadeVolume?(1)
        scheduleTimer()
    }

    func cancel() {
        stopTimer()
        timeRemaining = -1
        firedAt = nil
        lastDuration = nil
        onFadeVolume?(1)
    }

    func extend(by minutes: Double) {
        guard isActive, let deadline else { return }
        let extensionSeconds = minutes * 60
        self.deadline = deadline.addingTimeInterval(extensionSeconds)
        timeRemaining += extensionSeconds
        onFadeVolume?(1)
    }

    @discardableResult
    func checkAutoRestart() -> Bool {
        guard let firedAt,
              let lastDuration,
              Date().timeIntervalSince(firedAt) < autoRestartWindow,
              !isActive else { return false }
        start(seconds: lastDuration)
        return true
    }

    func restoreFullVolume() {
        onFadeVolume?(1)
    }

    static func gradualFadeVolume(remaining: TimeInterval) -> Float {
        let normalised = max(0, min(1, remaining / gradualFadeDuration))
        return Float(normalised * normalised * (3 - (2 * normalised)))
    }

    private func scheduleTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let deadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        timeRemaining = max(0, remaining)

        if remaining < Self.gradualFadeDuration {
            onFadeVolume?(Self.gradualFadeVolume(remaining: remaining))
        }

        if remaining <= 0 {
            stopTimer()
            timeRemaining = -1
            firedAt = Date()
            onFadeVolume?(0)
            onPause?()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        deadline = nil
    }
}
