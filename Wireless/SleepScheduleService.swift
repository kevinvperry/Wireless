import AVFoundation
import Combine
import Foundation

// Adapted from Autohop's SleepScheduleService (MIT — original Autohop code).
// "Sleep Schedule": the recurring nightly counterpart to the one-shot
// SleepTimerService. Owned by MobilePlayer, configured from
// SleepScheduleSettings and driven by MobilePlayer's 0.5 s tick via tick().
// When playback starts inside the nightly window the service arms a cycle:
// after the configured duration it fires onPrompt and plays a soft 60 s chime
// sequence through SleepScheduleChimePlayer — the station keeps playing under
// the chime. Play/pause (in the app, on the lock screen, in CarPlay or from an
// earbud), the in-app Still Listening button and the lock-screen notification
// action all count as "yes" (MobilePlayer calls userResponded(); the cycle
// restarts). If the chime finishes with no response, the listener is assumed
// asleep: onAsleep fires and MobilePlayer fades the station out and pauses.
// Wireless differences from Autohop: live radio has no episode boundary, so
// the End of Episode mode is omitted, and there is no rewind point to restore.
// A manual SleepTimerService activation suspends the schedule for the rest of
// the listening session (suspendForSession, called from MobilePlayer's tick).
// ACTIVE-WINDOW INVARIANT: every ongoing phase revalidates the configured time
// window. Crossing the end boundary cancels countdown/chime/notification state
// and returns to idle without pausing the station. A response received at or
// after the boundary also disarms instead of starting another prompt cycle.
// All methods must be called on the main actor.
@MainActor
final class SleepScheduleService: ObservableObject {

    // MARK: - Configuration (mirrors SleepScheduleSettings)

    struct Config: Equatable {
        var enabled: Bool
        /// Window start/end as minutes from midnight (e.g. 21:00 = 1260). The
        /// window may span midnight. Equal start and end = always in window.
        var startMinutes: Int
        var endMinutes: Int
        /// Minutes of playback between prompts.
        var durationMinutes: Int
    }

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        /// Counting down playback seconds until the next prompt.
        case counting(remaining: TimeInterval)
        /// Chime playing over the station, waiting up to 60 s for a "yes".
        case prompting
    }

    @Published private(set) var phase: Phase = .idle

    /// True while the "Are you still listening?" prompt is active.
    var isPrompting: Bool { phase == .prompting }

    /// Manual Sleep Timer was used — schedule stands down until the next
    /// listening session starts inside the window.
    private(set) var suspendedForSession = false

    private(set) var config = Config(enabled: false, startMinutes: 21 * 60, endMinutes: 6 * 60, durationMinutes: 20)

    // MARK: - Callbacks (wired and owned by MobilePlayer)

    /// Fired when the duration elapses. The station keeps playing; the chime
    /// starts immediately after.
    var onPrompt: (() -> Void)?

    /// Fired when the grace period passes with no response: MobilePlayer fades
    /// out and pauses the station.
    var onAsleep: (() -> Void)?

    /// Fired whenever the prompt is torn down for any reason (confirmed, timed
    /// out, suspended, or reset). MobilePlayer uses it to clear the lock-screen
    /// "Still Listening" notification. Safe to fire when no prompt was active.
    var onPromptDismissed: (() -> Void)?

    // MARK: - Internals

    private let chimePlayer = SleepScheduleChimePlayer()
    private var graceBackupTask: Task<Void, Never>?
    private let graceBackupSeconds: TimeInterval = 75   // safety net behind the 60 s chime

    // MARK: - Configuration updates

    /// Applies new settings. If the schedule was just enabled mid-session and
    /// we're playing inside the window, arm immediately.
    func updateConfig(_ newConfig: Config, isPlaying: Bool) {
        guard newConfig != config else { return }
        config = newConfig
        if !config.enabled {
            reset()
            return
        }
        // Moving the configured window so that "now" is outside it must end a
        // live countdown or prompt immediately, even before the next playback
        // tick arrives.
        if !isWithinWindow() {
            if phase != .idle {
                cancelPromptArtifacts()
                phase = .idle
            }
            return
        }
        // Re-arm with the new duration unless mid-prompt.
        if isPrompting { return }
        if isPlaying, !suspendedForSession, isWithinWindow() {
            arm()
        } else if !isPlaying {
            phase = .idle
        }
    }

    // MARK: - Session lifecycle (called by MobilePlayer)

    /// A fresh listening session started (play after a pause or a new
    /// station). Clears any manual-timer suspension and arms if inside the
    /// window.
    func playbackStarted() {
        // A stream reconnect while the prompt is live must not tear it down.
        if isPrompting { return }
        suspendedForSession = false
        cancelPromptArtifacts()
        guard config.enabled, isWithinWindow() else {
            phase = .idle
            return
        }
        arm()
    }

    /// The user set the manual Sleep Timer: stand down for this session.
    func suspendForSession() {
        guard !suspendedForSession else { return }
        suspendedForSession = true
        cancelPromptArtifacts()
        phase = .idle
    }

    /// Hard reset (schedule disabled).
    func reset() {
        suspendedForSession = false
        cancelPromptArtifacts()
        phase = .idle
    }

    // MARK: - Tick (called by MobilePlayer's 0.5 s timer)

    func tick(isPlaying: Bool) {
        // The active-hours window is a hard boundary, not merely an arming
        // condition. This check also tears down an already-visible prompt and
        // its lock-screen notification if the end time arrives during grace.
        guard enforceActiveWindow() else { return }
        guard case .counting(let remaining) = phase, isPlaying else { return }
        let next = remaining - 0.5
        if next <= 0 {
            beginPrompt()
        } else {
            phase = .counting(remaining: next)
        }
    }

    // MARK: - "Yes" response (called by MobilePlayer's transport paths)

    /// The user issued a transport command (play/pause) or tapped Still
    /// Listening while prompting. Stops the chime and re-arms a fresh cycle.
    func userResponded() {
        guard isPrompting else { return }
        cancelPromptArtifacts()
        if config.enabled, !suspendedForSession, isWithinWindow() {
            arm()
        } else {
            // A notification action can arrive just after the configured end
            // time. Treat it as dismissal only; never leak a new cycle beyond
            // the active window.
            phase = .idle
        }
    }

    // MARK: - Window maths

    /// True when `date` falls inside the configured nightly window. A window
    /// spanning midnight (start > end) is handled; start == end means the
    /// window is always active.
    func isWithinWindow(_ date: Date = Date()) -> Bool {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = config.startMinutes
        let end = config.endMinutes
        if start == end { return true }
        if start < end {
            return nowMinutes >= start && nowMinutes < end
        }
        // Spans midnight, e.g. 21:00–06:00.
        return nowMinutes >= start || nowMinutes < end
    }

    /// True while the schedule is enabled and the current time is inside the
    /// active-hours window — i.e. Sleep Schedule mode is potentially active.
    func isActive(_ date: Date = Date()) -> Bool {
        config.enabled && isWithinWindow(date)
    }

    /// Minutes (rounded up) left in the current pre-prompt countdown — the time
    /// until Sleep Schedule asks "still listening?". nil when not actively
    /// counting (paused, idle, or already prompting).
    var minutesUntilPrompt: Int? {
        if case .counting(let remaining) = phase {
            return max(1, Int(ceil(remaining / 60)))
        }
        return nil
    }

    // MARK: - Private

    /// Enforces the configured active-hours interval for every live phase.
    /// Returns false after disarming outside the window. Repeated idle ticks
    /// are intentionally side-effect free so notification clearing is emitted
    /// only when there was schedule state to tear down.
    @discardableResult
    private func enforceActiveWindow(_ date: Date = Date()) -> Bool {
        guard config.enabled, !suspendedForSession, isWithinWindow(date) else {
            if phase != .idle {
                cancelPromptArtifacts()
                phase = .idle
            }
            return false
        }
        return true
    }

    private func arm() {
        guard config.enabled, !suspendedForSession, isWithinWindow() else {
            phase = .idle
            return
        }
        phase = .counting(remaining: TimeInterval(max(1, config.durationMinutes)) * 60)
    }

    private func beginPrompt() {
        guard enforceActiveWindow() else { return }
        phase = .prompting
        onPrompt?()
        chimePlayer.play { [weak self] in
            Task { @MainActor in self?.assumeAsleep() }
        }
        graceBackupTask?.cancel()
        graceBackupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.graceBackupSeconds ?? 75))
            guard !Task.isCancelled else { return }
            self?.assumeAsleep()
        }
    }

    private func assumeAsleep() {
        guard isPrompting else { return }
        cancelPromptArtifacts()
        // Session is over — playbackStarted() re-arms on the next session.
        phase = .idle
        onAsleep?()
    }

    private func cancelPromptArtifacts() {
        chimePlayer.stop()
        graceBackupTask?.cancel()
        graceBackupTask = nil
        onPromptDismissed?()
    }
}

// MARK: - Settings

/// Wireless counterpart of Autohop's AppSettings.sleepSchedule* fields:
/// UserDefaults-backed so changes save immediately. Disabling keeps the saved
/// hours and interval for next time.
@MainActor
final class SleepScheduleSettings: ObservableObject {
    static let durationPresets = [10, 15, 20, 40, 60]

    private enum Key {
        static let enabled = "sleepScheduleEnabled"
        static let startMinutes = "sleepScheduleStartMinutes"
        static let endMinutes = "sleepScheduleEndMinutes"
        static let durationMinutes = "sleepScheduleDurationMinutes"
    }

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled); onChange?() } }
    @Published var startMinutes: Int { didSet { defaults.set(startMinutes, forKey: Key.startMinutes); onChange?() } }
    @Published var endMinutes: Int { didSet { defaults.set(endMinutes, forKey: Key.endMinutes); onChange?() } }
    @Published var durationMinutes: Int { didSet { defaults.set(durationMinutes, forKey: Key.durationMinutes); onChange?() } }

    /// Wired by MobilePlayer to push the new configuration into the service.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Key.enabled)
        startMinutes = (defaults.object(forKey: Key.startMinutes) as? Int) ?? 21 * 60
        endMinutes = (defaults.object(forKey: Key.endMinutes) as? Int) ?? 6 * 60
        let duration = (defaults.object(forKey: Key.durationMinutes) as? Int) ?? 20
        durationMinutes = Self.durationPresets.contains(duration) ? duration : 20
    }

    var config: SleepScheduleService.Config {
        .init(enabled: enabled, startMinutes: startMinutes, endMinutes: endMinutes, durationMinutes: durationMinutes)
    }
}

// MARK: - Chime player

/// Plays the 60-second "Are you still listening?" prompt audio over the
/// continuing station playback: a soft singing-bowl-style tone at 0 s, 20 s
/// and 40 s with silence between, generated as a single in-memory WAV so
/// AVAudioPlayer keeps rendering for the whole grace period (which also keeps
/// the app from being suspended while backgrounded). Deliberately meditative —
/// slow ~0.5 s attack, long gentle decay, low-mid pitch — so it cues an awake
/// listener without startling one who is drifting off. The completion fires
/// when the full 60 s plays out with no interruption — i.e. no response.
@MainActor
final class SleepScheduleChimePlayer: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?
    private var onFinished: (() -> Void)?

    private static let sampleRate = 22050.0
    private static let totalSeconds = 60.0
    private static let chimeOffsets: [Double] = [0, 20, 40]

    func play(onFinished: @escaping () -> Void) {
        stop()
        self.onFinished = onFinished
        do {
            let player = try AVAudioPlayer(data: Self.chimeWAVData)
            player.delegate = self
            player.volume = 0.38
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // Audio failed — fall back to the service's backup grace task.
            self.player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        onFinished = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            let callback = self.onFinished
            self.player = nil
            self.onFinished = nil
            callback?()
        }
    }

    // MARK: - Generated audio

    /// 60 s mono 16-bit WAV: a singing-bowl-style swell (slow attack, ≈7 s
    /// decay) built from a low C4 fundamental with quiet harmonic partials,
    /// repeated at each offset. Built once and cached.
    private static let chimeWAVData: Data = {
        let sampleRate = SleepScheduleChimePlayer.sampleRate
        let totalFrames = Int(SleepScheduleChimePlayer.totalSeconds * sampleRate)
        var samples = [Int16](repeating: 0, count: totalFrames)

        func addTone(frequency: Double, startSecond: Double, duration: Double, amplitude: Double) {
            let startFrame = Int(startSecond * sampleRate)
            let frames = Int(duration * sampleRate)
            for i in 0..<frames {
                let frame = startFrame + i
                guard frame < totalFrames else { break }
                let t = Double(i) / sampleRate
                // Slow half-sine swell over the first 0.5 s, then a long
                // gentle decay with a fade floor at the end of the tone.
                let attack = min(1.0, t / 0.5)
                let attackCurve = sin(attack * .pi / 2)
                let decay = exp(-0.55 * t)
                let release = min(1.0, (duration - t) / 0.8)
                let envelope = attackCurve * decay * max(0, release)
                let value = sin(2 * .pi * frequency * t) * envelope * amplitude
                let mixed = Double(samples[frame]) + value * Double(Int16.max)
                samples[frame] = Int16(max(Double(Int16.min), min(Double(Int16.max), mixed)))
            }
        }

        for offset in SleepScheduleChimePlayer.chimeOffsets {
            // Singing-bowl voicing: C4 fundamental + soft octave and twelfth.
            addTone(frequency: 261.63, startSecond: offset, duration: 7.0, amplitude: 0.22)       // C4
            addTone(frequency: 523.25, startSecond: offset, duration: 6.0, amplitude: 0.08)       // C5 partial
            addTone(frequency: 784.0, startSecond: offset, duration: 4.5, amplitude: 0.035)       // G5 partial
        }

        // Minimal PCM WAV container.
        var data = Data()
        let byteRate = UInt32(sampleRate) * 2
        let dataSize = UInt32(samples.count * 2)
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(16)
        append16(1)                       // PCM
        append16(1)                       // mono
        append(UInt32(sampleRate))
        append(byteRate)
        append16(2)                       // block align
        append16(16)                      // bits per sample
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }()
}
