import SwiftUI
import AVFoundation
import MediaPlayer
import Network
import Combine
import UIKit

private final class NowPlayingImageBox: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

/// MediaPlayer invokes artwork request handlers on its private access queue.
/// Keep this factory outside MobilePlayer's main-actor isolation so that call is valid.
private func makeNowPlayingArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    let box = NowPlayingImageBox(image)
    return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in box.image }
}

/// Radio-specific adaptation of Autohop's NowPlayingService and audio route handling.
@MainActor
final class MobilePlayer: ObservableObject {
    /// Shared by the iPhone window and the CarPlay scene so both drive one player.
    static let shared = MobilePlayer()
    static let syncEnabledDefaultsKey = "syncEnabled"
    static let syncDefaultOffMigrationKey = "syncEnabledDefaultOffMigration.v1"

    @Published var syncEnabled: Bool {
        didSet {
            defaults.set(syncEnabled, forKey: Self.syncEnabledDefaultsKey)
            directoryAudio.setSyncEnabled(syncEnabled)
            applyTrackMetadata(nil, source: "settings.tv-sync")
            startCompanionMetadataIfNeeded()
            if !syncEnabled { measured = nil }
            publishNowPlaying()
            diagnose("settings.sync", syncEnabled ? "TV Sync enabled" : "TV Sync disabled", metadata: ["delaySeconds": String(format: "%.1f", delay)])
        }
    }
    @Published var vocalBoost: VocalBoostLevel {
        didSet {
            defaults.set(vocalBoost.rawValue, forKey: "vocalBoostLevel")
            if vocalBoost != .off, musicPreset != .off { musicPreset = .off }
            directoryAudio.setSoundControls(vocalBoost, musicPreset: musicPreset)
            applyTrackMetadata(nil, source: "settings.vocal-boost")
            startCompanionMetadataIfNeeded()
            publishNowPlaying()
            diagnose("settings.vocalBoost", "Vocal Boost changed", metadata: ["level": vocalBoost.rawValue])
        }
    }
    @Published var musicPreset: MusicPreset {
        didSet {
            defaults.set(musicPreset.rawValue, forKey: "musicPresetLevel")
            if musicPreset != .off, vocalBoost != .off { vocalBoost = .off }
            directoryAudio.setSoundControls(vocalBoost, musicPreset: musicPreset)
            diagnose("settings.musicPreset", "Music preset changed", metadata: ["level": musicPreset.rawValue])
        }
    }
    @Published var delay: Double = UserDefaults.standard.double(forKey: "selectedDelaySeconds") {
        didSet {
            UserDefaults.standard.set(delay, forKey: "selectedDelaySeconds")
            directoryAudio.setDelay(delay)
        }
    }
    @Published private(set) var station: DirectoryStation
    @Published private(set) var trackMetadata: StreamTrackMetadata?
    @Published private(set) var audioEffectState: VocalBoostState = .off
    var vocalBoostState: VocalBoostState { musicPreset != .off ? .off : audioEffectState }
    var musicPresetState: VocalBoostState { musicPreset != .off ? audioEffectState : .off }
    @Published private(set) var supportsDelay = false
    @Published var selectedStreamID = "" { didSet {
        guard oldValue != selectedStreamID else { return }
        if station.playableStreams.contains(where: { $0.id == selectedStreamID }) {
            defaults.set(selectedStreamID, forKey: streamSelectionKey(for: station.id))
        }
        let shouldResume = requested
        directoryAudio.configure(station, streamID: selectedStreamID)
        if shouldResume {
            requested = true
            directoryAudio.start()
            startCompanionMetadataIfNeeded()
        }
    } }
    let library: StationLibrary
    let statsStore: WirelessListeningStatsStore
    let sleepTimer = SleepTimerService()
    let sleepSchedule = SleepScheduleService()
    let sleepScheduleSettings = SleepScheduleSettings()
    private var sleepScheduleTimer: Timer?
    private var sleepScheduleFadeTask: Task<Void, Never>?
    private let directoryAudio = DirectoryAudio()
    private let companionMetadata = CompanionMetadataProvider()
    private let defaults: UserDefaults

    var shouldOpenDiscoverOnLaunch: Bool {
        station.id == DirectoryStation.unselected.id && library.favourites.isEmpty
    }
    var hasDetails: Bool {
        station.id != DirectoryStation.unselected.id
    }
    var displayTitle: String {
        guide.current?.name ?? (station.id == DirectoryStation.unselected.id ? "Live radio" : station.name)
    }

    private func streamSelectionKey(for stationID: String) -> String {
        "selectedStreamID.v1.\(stationID)"
    }

    private func savedStreamID(for station: DirectoryStation) -> String? {
        guard let saved = defaults.string(forKey: streamSelectionKey(for: station.id)),
              station.playableStreams.contains(where: { $0.id == saved }) else { return nil }
        return saved
    }

    func playStation(_ value: DirectoryStation) {
        let changingStation = station.id != value.id
        pause()
        if changingStation && syncEnabled { syncEnabled = false }
        syncBufferRemaining = nil
        diagnose("station.selected", "Station selected", metadata: ["stationID": value.id, "stationName": value.name])
        applyTrackMetadata(nil, source: "station-change")
        station = value; supportsDelay = false; measured = nil
        resetNowPlayingArtwork()
        let nextStreamID = savedStreamID(for: value) ?? value.preferredStream?.id ?? ""
        if selectedStreamID == nextStreamID {
            directoryAudio.configure(value, streamID: nextStreamID)
        } else { selectedStreamID = nextStreamID }
        directoryAudio.setDelay(delay)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "lastPlayedStation.v1") }
        library.recordRecent(value)
        refreshDetails()
        play()
    }
    private func startEngine() {
        directoryAudio.start()
        startCompanionMetadataIfNeeded()
    }
    private func reconnectEngine() { directoryAudio.reconnect() }
    @Published private(set) var requested = false
    @Published private(set) var status = "Ready to play"
    @Published private(set) var detail = "Choose a station in Discover"
    @Published private(set) var buffering = false
    @Published private(set) var progress = 0.0
    @Published private(set) var syncBufferRemaining: Double?
    @Published private(set) var measured: Double?
    @Published private(set) var route = "This device"
    let guide = ProgrammeGuide()
    private let monitor = NWPathMonitor()
    private var subscriptions = Set<AnyCancellable>()
    private var widgetCoordinator: WidgetSnapshotCoordinator?

    func publishWidgetSnapshot() {
        if widgetCoordinator == nil { widgetCoordinator = WidgetSnapshotCoordinator(player: self) }
        else { widgetCoordinator?.publish(player: self) }
    }

    private var resumeAfterInterruption = false
    private var hadConnection = true
    private var isForeground = true
    private var lastMetadata = ""
    private var trackMetadataSource: String?
    private var companionMetadataEnabled = false
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkRequestURL: URL?
    private var artworkTask: Task<Void, Never>?
    private var activationID = UUID()
    private var recoveryTask: UIBackgroundTaskIdentifier = .invalid
    private var recoveryGraceUsed = false
    private var bufferingStartedAt: Date?
    private var lastDiagnosticStatus = ""
    private var lastMeasuredDiagnosticAt = Date.distantPast
    private var lastMeasuredDiagnosticValue: Double?
    private let metadataFreshnessPolicy = MetadataFreshnessPolicy()
    private var displayedMetadataFirstSeenAt: Date?
    private var displayedMetadataLastSeenAt: Date?
    private var displayedMetadataReceiptCount = 0
    private var displayedMetadataHints: [String] = []
    private var displayedMetadataEmbeddedTimestamp: Date?
    private var expiredMetadataThisSession: StreamTrackMetadata?
    private var lastStaleDiagnosticSignature: String?
    private var lastStaleDiagnosticAt = Date.distantPast
    private var suppressedStaleDiagnosticCount = 0

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }

    init(
        defaults: UserDefaults = .standard,
        statsStore: WirelessListeningStatsStore = .shared
    ) {
        let initialSyncEnabled: Bool
        if defaults.bool(forKey: Self.syncDefaultOffMigrationKey) {
            initialSyncEnabled = defaults.object(forKey: Self.syncEnabledDefaultsKey) as? Bool ?? false
        } else {
            // One-time product-default migration. This deliberately resets TV Sync
            // for existing installations when they first run this build, then
            // preserves the user's choice on every subsequent launch.
            initialSyncEnabled = false
            defaults.set(false, forKey: Self.syncEnabledDefaultsKey)
            defaults.set(true, forKey: Self.syncDefaultOffMigrationKey)
        }
        _syncEnabled = Published(initialValue: initialSyncEnabled)
        let savedMusicPreset = MusicPreset(rawValue: defaults.string(forKey: "musicPresetLevel")
            ?? defaults.string(forKey: "bassBoostLevel") ?? "")
            ?? (defaults.bool(forKey: "deepBassEnabled") ? .deep : .off)
        _musicPreset = Published(initialValue: savedMusicPreset)
        _vocalBoost = Published(initialValue: savedMusicPreset != .off ? .off : VocalBoostLevel(
            rawValue: defaults.string(forKey: "vocalBoostLevel") ?? "off"
        ) ?? .off)
        self.defaults = defaults
        self.statsStore = statsStore
        let library = StationLibrary(defaults: defaults)
        self.library = library
        let saved = defaults.data(forKey: "lastPlayedStation.v1").flatMap { try? JSONDecoder().decode(DirectoryStation.self, from: $0) }
        let selected = saved.flatMap { saved in library.stations.first(where: { $0.id == saved.id }) ?? library.favourites.first(where: { $0.id == saved.id }) ?? saved } ?? .unselected
        self.station = selected
        self.selectedStreamID = defaults.string(forKey: "selectedStreamID.v1.\(selected.id)")
            .flatMap { saved in selected.playableStreams.contains(where: { $0.id == saved }) ? saved : nil }
            ?? selected.preferredStream?.id ?? ""
        delay = min(30, max(0, (delay * 2).rounded() / 2))
        directoryAudio.onStatus = { [weak self] update, supported in
            guard let self else { return }
            self.recordPlaybackStatus(update, supportsDelay: supported)
            self.requested = update.active; self.status = update.title; self.detail = update.detail
            self.syncBufferRemaining = update.syncBufferRemaining
            self.buffering = update.buffering; self.progress = update.progress; self.measured = update.measuredDelay
            if !update.active { self.companionMetadata.stop() }
            self.supportsDelay = supported; self.updateRecoveryGrace(); self.publishNowPlaying()
        }
        directoryAudio.onTrackMetadata = { [weak self] evaluation in
            guard let self else { return }
            guard let evaluation else {
                self.applyTrackMetadata(nil, source: "embedded-reset")
                return
            }
            if self.syncEnabled {
                self.diagnose("metadata.displaySuppressed", "Track metadata suppressed", metadata: [
                    "reason": "tv-sync", "source": "embedded", "stationID": self.station.id,
                    "stationName": self.station.name
                ])
                return
            }
            self.applyMetadataEvaluation(evaluation, source: "embedded")
        }
        directoryAudio.onAudioEffectState = { [weak self] state in
            self?.audioEffectState = state
        }
        directoryAudio.onPlaybackInterval = { [weak self] seconds, endedAt in
            guard let self else { return }
            self.statsStore.recordRendered(
                seconds: seconds,
                station: self.station,
                mode: self.listeningMode,
                route: self.audioRouteCategory,
                endedAt: endedAt
            )
        }
        directoryAudio.setSyncEnabled(syncEnabled)
        directoryAudio.setSoundControls(vocalBoost, musicPreset: musicPreset)
        directoryAudio.setDelay(delay)
        sleepTimer.onFadeVolume = { [weak self] volume in
            self?.directoryAudio.setVolume(volume)
        }
        sleepTimer.onPause = { [weak self] in
            guard let self, self.requested else { return }
            self.pause()
        }
        configureSleepSchedule()
        if selected.preferredStream != nil { directoryAudio.configure(selected, streamID: selectedStreamID) }
        registerRemoteControls()
        if #available(iOS 27.0, *) {
            NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)
                .receive(on: DispatchQueue.main).sink { [weak self] note in
                    guard let self else { return }
                    let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                    // App/scene deactivation is not a playback interruption. Only
                    // tear down audio when another system audio session interrupted it.
                    guard context?.interruptionContext != nil else { return }
                    self.handleInterruptionBegan()
                }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: AVAudioSession.resumptionRecommendationNotification)
                .receive(on: DispatchQueue.main).sink { [weak self] note in
                    guard let self else { return }
                    let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                    self.handleInterruptionEnded(shouldResume: context?.recommendation == .shouldResume)
                }.store(in: &subscriptions)
        } else {
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
                .receive(on: DispatchQueue.main).sink { [weak self] note in
                    guard let self,
                          let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                    if type == .began {
                        self.handleInterruptionBegan()
                    } else {
                        let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                        self.handleInterruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
                    }
                }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                guard let self else { return }
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                self.diagnose("audio.routeChanged", "Audio route changed", metadata: ["reason": reason.map(String.init) ?? "unknown"])
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.pause() }
                self.refreshRoute()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.refreshRoute()
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.requested else { return }
                self.diagnose("audio.mediaServicesReset", "Audio services reset while playing")
                self.play()
                self.reconnectEngine()
            }.store(in: &subscriptions)
        guide.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
                self?.publishNowPlaying()
            }
        }.store(in: &subscriptions)
        library.$stations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stations in
                guard let self,
                      let refreshed = stations.first(where: { $0.id == self.station.id }),
                      refreshed != self.station else { return }
                self.station = refreshed
                if let data = try? JSONEncoder().encode(refreshed) {
                    self.defaults.set(data, forKey: "lastPlayedStation.v1")
                }
                self.resetNowPlayingArtwork()
                self.refreshDetails()
                self.publishNowPlaying()
            }
            .store(in: &subscriptions)
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if connected != self.hadConnection {
                    self.diagnose("network.path", connected ? "Network connection restored" : "Network connection lost", metadata: ["playing": "\(self.requested)"])
                }
                if connected && !self.hadConnection && self.requested { self.reconnectEngine() }
                self.hadConnection = connected
            }
        }
        monitor.start(queue: DispatchQueue(label: "Wireless.connectivity"))
        refreshRoute()
        refreshDetails()
    }

    func prepareAudio() {
        guard hasDetails, !requested else { return }
        directoryAudio.prepare()
    }

    func play() {
        diagnose("player.play", "Play requested", metadata: ["stationID": station.id, "streamID": selectedStreamID])
        cancelSleepScheduleFade()
        if !sleepTimer.checkAutoRestart() {
            sleepTimer.restoreFullVolume()
        }
        // Starting from a pause begins a new listening session for Sleep
        // Schedule (Autohop arms on each playback start).
        if !requested { sleepSchedule.playbackStarted() }
        let token = UUID()
        activationID = token
        requested = true
        resumeAfterInterruption = false
        status = "Connecting…"
        if ProcessInfo.processInfo.isiOSAppOnMac {
            // AVAudioSession activation is not implemented for iPhone/iPad
            // apps running on Mac. macOS owns the audio route and AVPlayer /
            // AVAudioEngine can start without an explicit iOS session.
            diagnose("audio.activationBypassed", "Audio session activation bypassed", metadata: ["platform": "iOS-on-Mac"])
            startEngine()
            refreshRoute()
            publishNowPlaying()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Sound presets are DSP choices, not session/route changes. Changing
            // session mode during playback can invalidate a running audio graph.
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            if #available(iOS 27.0, *) {
                session.activate(options: []) { [weak self] activated, error in
                    Task { @MainActor in
                        guard let self, self.activationID == token, self.requested else { return }
                        guard activated, error == nil else {
                            self.diagnose("audio.activationFailed", "Audio session could not be activated", metadata: ["error": error?.localizedDescription ?? "unknown"])
                            self.requested = false
                            self.status = "Audio unavailable"
                            self.detail = error?.localizedDescription ?? "Please try again."
                            return
                        }
                        self.startEngine()
                        self.refreshRoute()
                        self.publishNowPlaying()
                    }
                }
            } else {
                try session.setActive(true)
                startEngine()
                refreshRoute()
                publishNowPlaying()
            }
        } catch {
            diagnose("audio.configurationFailed", "Audio session could not be configured", metadata: ["error": error.localizedDescription])
            requested = false
            status = "Audio unavailable"
            detail = error.localizedDescription
        }
    }

    private func handleInterruptionBegan() {
        diagnose("audio.interrupted", "System audio interruption began", metadata: ["wasPlaying": "\(requested)"])
        let wasRequested = requested
        pause()
        resumeAfterInterruption = wasRequested
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        if resumeAfterInterruption && shouldResume {
            diagnose("audio.interruptionResume", "System recommended resuming playback")
            play()
        }
        resumeAfterInterruption = false
    }

    func pause() {
        if requested { diagnose("player.pause", "Pause requested", metadata: ["stationID": station.id, "streamID": selectedStreamID]) }
        activationID = UUID()
        requested = false
        companionMetadata.stop()
        cancelSleepScheduleFade()
        endRecoveryGrace()
        resumeAfterInterruption = false
        directoryAudio.stop()
        statsStore.endSession(reason: .paused)
        statsStore.checkpoint()
        buffering = false; status = "Paused"
        publishNowPlaying()
    }

    static let autoResumeKey = "autoResumePlayback"
    private var hasAttemptedAutoResume = false

    /// Resumes the last played station once per launch when Auto Resume is on.
    func autoResumeIfEnabled() {
        guard !hasAttemptedAutoResume else { return }
        hasAttemptedAutoResume = true
        guard defaults.bool(forKey: Self.autoResumeKey), hasDetails, !requested,
              station.preferredStream != nil else { return }
        diagnose("player.autoResume", "Auto Resume started the last played station", metadata: ["stationID": station.id])
        play()
    }

    func toggle() {
        respondToSleepSchedulePrompt(via: "play/pause")
        requested ? pause() : play()
    }

    /// Answers the Sleep Schedule "still listening?" prompt. Any play/pause
    /// command while prompting counts as a response, as in Autohop.
    func respondToSleepSchedulePrompt(via source: String) {
        guard sleepSchedule.isPrompting else { return }
        sleepSchedule.userResponded()
        diagnose("sleepSchedule.stillListening", "Listener confirmed still listening", metadata: ["source": source])
    }

    // MARK: - Sleep Schedule

    private func configureSleepSchedule() {
        sleepScheduleSettings.onChange = { [weak self] in
            guard let self else { return }
            self.sleepSchedule.updateConfig(self.sleepScheduleSettings.config, isPlaying: self.requested)
        }
        sleepSchedule.updateConfig(sleepScheduleSettings.config, isPlaying: requested)
        sleepSchedule.onPrompt = { [weak self] in
            NotificationService.shared.postSleepSchedulePrompt()
            self?.diagnose("sleepSchedule.prompt", "Sleep Schedule asking if still listening (playback continues)")
        }
        sleepSchedule.onPromptDismissed = {
            NotificationService.shared.clearSleepSchedulePrompt()
        }
        NotificationService.shared.setStillListeningHandler { [weak self] in
            self?.respondToSleepSchedulePrompt(via: "notification")
        }
        // Adapted from Autohop's PlaybackCoordinator: fade over the Sleep Timer's
        // 30 s curve, then pause. Live radio has no prompt point to rewind to.
        sleepSchedule.onAsleep = { [weak self] in
            guard let self, self.requested else { return }
            self.sleepScheduleFadeTask?.cancel()
            self.sleepScheduleFadeTask = Task { @MainActor [weak self] in
                var remaining = SleepTimerService.gradualFadeDuration
                while remaining > 0 {
                    guard !Task.isCancelled, let self else { return }
                    self.directoryAudio.setVolume(SleepTimerService.gradualFadeVolume(remaining: remaining))
                    try? await Task.sleep(for: .milliseconds(500))
                    remaining -= 0.5
                }
                guard !Task.isCancelled, let self else { return }
                self.directoryAudio.setVolume(0)
                self.sleepScheduleFadeTask = nil
                self.pause()
                self.directoryAudio.setVolume(1)
                self.diagnose("sleepSchedule.asleep", "No response to prompt — faded out and paused", metadata: [
                    "fadeSeconds": "\(Int(SleepTimerService.gradualFadeDuration))"
                ])
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.sleepTimer.isActive { self.sleepSchedule.suspendForSession() }
                self.sleepSchedule.tick(isPlaying: self.requested)
                self.expireStaleMetadataIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepScheduleTimer = timer
    }

    private func cancelSleepScheduleFade() {
        guard let task = sleepScheduleFadeTask else { return }
        task.cancel()
        sleepScheduleFadeTask = nil
        directoryAudio.setVolume(1)
    }
    func adjust(_ amount: Double) { delay = min(30, max(0, delay + amount)) }
    func sceneChanged(_ phase: ScenePhase) {
        diagnose("app.scene", "Scene phase changed", metadata: ["phase": String(describing: phase), "playing": "\(requested)", "buffering": "\(buffering)"])
        isForeground = phase == .active
        if isForeground { recoveryGraceUsed = false; endRecoveryGrace() }
        if phase == .active {
            refreshRoute()
            refreshDetails()
            if requested && buffering { reconnectEngine() }
            publishNowPlaying()
        } else {
            if phase == .background && !requested { directoryAudio.stop() }
            updateRecoveryGrace()
            statsStore.checkpoint()
        }
    }

    private func recordPlaybackStatus(_ update: PlaybackStatus, supportsDelay: Bool) {
        let statusKey = "\(update.active)|\(update.buffering)|\(update.title)|\(supportsDelay)"
        if update.buffering, bufferingStartedAt == nil { bufferingStartedAt = Date() }
        if !update.active {
            statsStore.endSession(reason: .playbackEnded)
            statsStore.checkpoint()
        }
        if !update.buffering, let started = bufferingStartedAt {
            diagnose("playback.bufferingEnded", "Buffering ended", metadata: [
                "durationSeconds": String(format: "%.2f", Date().timeIntervalSince(started)),
                "stationID": station.id,
                "streamID": directoryAudio.selectedStreamID ?? selectedStreamID
            ])
            bufferingStartedAt = nil
        }
        if statusKey != lastDiagnosticStatus {
            diagnose("playback.state", update.title, metadata: [
                "active": "\(update.active)",
                "buffering": "\(update.buffering)",
                "supportsDelay": "\(supportsDelay)",
                "stationID": station.id,
                "streamID": directoryAudio.selectedStreamID ?? selectedStreamID
            ])
            lastDiagnosticStatus = statusKey
        }
        if let measured = update.measuredDelay,
           Date().timeIntervalSince(lastMeasuredDiagnosticAt) >= 15 || abs(measured - (lastMeasuredDiagnosticValue ?? measured)) >= 0.75 {
            diagnose("sync.measurement", "Measured stream delay", metadata: [
                "measuredSeconds": String(format: "%.2f", measured),
                "selectedSeconds": String(format: "%.2f", delay),
                "stationID": station.id,
                "streamID": directoryAudio.selectedStreamID ?? selectedStreamID
            ])
            lastMeasuredDiagnosticAt = Date()
            lastMeasuredDiagnosticValue = measured
        }
    }
    private func endRecoveryGrace() {
        if recoveryTask != .invalid {
            UIApplication.shared.endBackgroundTask(recoveryTask)
            recoveryTask = .invalid
        }
    }
    private func updateRecoveryGrace() {
        if !buffering || !requested {
            endRecoveryGrace()
            if !buffering { recoveryGraceUsed = false }
        } else if !isForeground && !recoveryGraceUsed {
            recoveryGraceUsed = true
            recoveryTask = UIApplication.shared.beginBackgroundTask(withName: "Reconnect radio") { [weak self] in
                Task { @MainActor in self?.endRecoveryGrace() }
            }
        }
    }
    private func refreshRoute() {
        route = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "This device"
    }

    private var listeningMode: WirelessListeningMode {
        if syncEnabled { return .tvSync }
        if musicPreset != .off, musicPresetState.isActive { return musicPreset == .popRnB ? .popRnB : musicPreset == .mid ? .midBass : .deepBass }
        if vocalBoost != .off, vocalBoostState.isActive { return .vocalBoost }
        return .live
    }

    private var audioRouteCategory: WirelessAudioRouteCategory {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return .thisDevice }
        switch output.portType {
        case .builtInSpeaker, .builtInReceiver:
            return .thisDevice
        case .headphones, .headsetMic, .usbAudio:
            return .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth
        case .airPlay:
            return .airPlay
        case .carAudio:
            return .carPlay
        default:
            return .other
        }
    }
    private func registerRemoteControls() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in Task { @MainActor in
            self?.respondToSleepSchedulePrompt(via: "remote play")
            self?.play()
        }; return .success }
        centre.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in
            self?.respondToSleepSchedulePrompt(via: "remote pause")
            self?.pause()
        }; return .success }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        for command in [centre.nextTrackCommand, centre.previousTrackCommand, centre.skipForwardCommand,
                        centre.skipBackwardCommand, centre.changePlaybackPositionCommand, centre.changePlaybackRateCommand] {
            command.isEnabled = false
        }
    }
    private func publishNowPlaying() {
        let metadata = syncEnabled ? nil : trackMetadata
        let text = NowPlayingTextProjection.make(
            stationName: station.name,
            network: station.network,
            location: station.location,
            frequency: station.frequency,
            track: metadata
        )
        let audible = requested && status == "Playing"
        requestNowPlayingArtworkIfNeeded()
        let key = "\(station.id)|\(text.title)|\(text.artist)|\(text.album)|\(audible)|\(nowPlayingArtwork != nil)"
        guard key != lastMetadata else { return }
        lastMetadata = key
        var information: [String: Any] = [
            MPMediaItemPropertyTitle: text.title,
            MPMediaItemPropertyArtist: text.artist,
            MPMediaItemPropertyAlbumTitle: text.album,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: audible ? 1.0 : 0.0
        ]
        if let nowPlayingArtwork { information[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = information
    }

    private func resetNowPlayingArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkRequestURL = nil
        nowPlayingArtwork = nil
        lastMetadata = ""
    }

    private func requestNowPlayingArtworkIfNeeded() {
        guard nowPlayingArtwork == nil,
              let url = URL(string: station.logo_url),
              url.scheme?.lowercased() == "https",
              artworkRequestURL != url else { return }
        artworkRequestURL = url
        let stationID = station.id
        artworkTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let source = UIImage(data: data),
                      let self,
                      self.station.id == stationID else { return }
                let image = Self.whiteBackedArtwork(source)
                self.nowPlayingArtwork = makeNowPlayingArtwork(image)
                self.lastMetadata = ""
                self.publishNowPlaying()
            } catch is CancellationError { }
            catch { }
        }
    }

    private static func whiteBackedArtwork(_ source: UIImage) -> UIImage {
        let canvas = CGSize(width: 1_024, height: 1_024)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            guard source.size.width > 0, source.size.height > 0 else { return }
            let scale = max(canvas.width / source.size.width, canvas.height / source.size.height)
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: CGRect(x: (canvas.width - size.width) / 2,
                                   y: (canvas.height - size.height) / 2,
                                   width: size.width,
                                   height: size.height))
        }
    }

    private func refreshDetails() {
        if let channelID = station.senChannelID { guide.start(channelID: channelID) }
        else if let source = station.taptProgrammeSource {
            guide.startTapt(website: source.website, timeZoneIdentifier: source.timeZoneIdentifier)
        }
        else if let serviceID = station.abcProgrammeServiceID { guide.startABC(serviceID: serviceID) }
        else { guide.stop() }
    }

    private func startCompanionMetadataIfNeeded() {
        companionMetadata.stop()
        companionMetadataEnabled = false
        directoryAudio.setCompanionMetadataPreferred(false)
        guard requested else {
            diagnose("metadata.providerDecision", "Companion metadata unavailable", metadata: [
                "reason": "playback-not-requested", "stationID": station.id, "stationName": station.name
            ])
            return
        }
        guard !syncEnabled else {
            diagnose("metadata.providerDecision", "Companion metadata unavailable", metadata: [
                "reason": "tv-sync-enabled", "stationID": station.id, "stationName": station.name
            ])
            return
        }
        let stationID = station.id
        companionMetadataEnabled = CompanionMetadataSource.source(for: station, selectedStreamID: selectedStreamID) != nil
        directoryAudio.setCompanionMetadataPreferred(companionMetadataEnabled)
        companionMetadata.start(station: station, selectedStreamID: selectedStreamID) { [weak self] evaluation in
            guard let self, self.requested, !self.syncEnabled, self.station.id == stationID else { return }
            self.applyMetadataEvaluation(evaluation, source: "companion")
        }
    }

    private func applyMetadataEvaluation(_ evaluation: StreamTrackMetadataEvaluation, source: String) {
        let preferredSource = companionMetadataEnabled ? "companion" : "embedded"
        let previousSource = trackMetadataSource ?? "none"
        let now = Date()
        let action: String
        let reason: String

        if let receivedMetadata = evaluation.metadata {
            let metadata: StreamTrackMetadata
            let sameSongAsDisplayed: Bool
            if let displayed = trackMetadata, displayed.hasSameSong(as: receivedMetadata) {
                metadata = displayed.mergingAlbum(from: receivedMetadata)
                sameSongAsDisplayed = true
            } else {
                metadata = receivedMetadata
                sameSongAsDisplayed = false
            }
            let timestampDetails = metadataFreshnessPolicy.diagnosticDetails(for: evaluation, at: now)
            let timestampIsStale = timestampDetails["candidateTimestampStale"] == "true"
            let expiredAndUnchanged = expiredMetadataThisSession == metadata
            if timestampIsStale || expiredAndUnchanged {
                let staleCandidateCanClearDisplay = trackMetadata != nil
                    && (trackMetadataSource == source || source == preferredSource)
                action = staleCandidateCanClearDisplay ? "cleared-stale" : "suppressed-stale"
                reason = timestampIsStale ? "embedded-timestamp-stale" : "session-expired-unchanged"
                recordStaleMetadata(
                    metadata,
                    evaluation: evaluation.addingProviderDetails(timestampDetails),
                    source: source,
                    reason: reason,
                    now: now,
                    onlyOnce: expiredAndUnchanged
                )
                expiredMetadataThisSession = metadata
                if staleCandidateCanClearDisplay {
                    applyTrackMetadata(nil, source: "stale-metadata", resetFreshness: false)
                }
            } else {
                if expiredMetadataThisSession != nil { expiredMetadataThisSession = nil }
                action = trackMetadata == metadata ? "retained-unchanged" : "displayed"
                reason = sameSongAsDisplayed
                    ? "same-song-metadata-merged"
                    : (source == preferredSource ? "preferred-source-accepted" : "fallback-source-accepted")
                if trackMetadata == metadata {
                    displayedMetadataLastSeenAt = now
                    displayedMetadataReceiptCount += 1
                } else {
                    applyTrackMetadata(
                        metadata,
                        source: sameSongAsDisplayed ? (trackMetadataSource ?? source) : source
                    )
                    displayedMetadataFirstSeenAt = now
                    displayedMetadataLastSeenAt = now
                    displayedMetadataReceiptCount = 1
                    displayedMetadataHints = evaluation.classificationHints
                    displayedMetadataEmbeddedTimestamp = metadataFreshnessPolicy.embeddedTimestamp(in: evaluation)
                }
            }
        } else if !MetadataSourceArbitration.shouldApplyEmptyResult(
            source: source,
            companionEnabled: companionMetadataEnabled,
            currentSource: trackMetadataSource
        ) {
            action = "suppressed"
            reason = trackMetadataSource == "companion"
                ? "lower-priority-empty-cannot-clear-companion"
                : "lower-priority-empty-with-companion-enabled"
        } else {
            action = trackMetadata == nil ? "retained-empty" : "cleared"
            reason = source == preferredSource ? "preferred-source-rejected-or-empty" : "active-source-rejected-or-empty"
            applyTrackMetadata(nil, source: source)
        }

        var fields = evaluation.diagnosticFields
        fields.merge([
            "action": action,
            "affectsDisplay": "\(["displayed", "cleared", "cleared-stale"].contains(action))",
            "currentDisplaySourceBeforeDecision": previousSource,
            "preferredSource": preferredSource,
            "reason": reason,
            "source": source,
            "stationID": station.id,
            "stationName": station.name
        ]) { _, new in new }
        diagnose("metadata.displayDecision", "Metadata display decision recorded", metadata: fields)
    }

    private func applyTrackMetadata(_ metadata: StreamTrackMetadata?, source: String, resetFreshness: Bool = true) {
        guard trackMetadata != metadata else {
            if metadata != nil { trackMetadataSource = source }
            return
        }
        let previous = trackMetadata
        trackMetadata = metadata
        trackMetadataSource = metadata == nil ? nil : source
        if metadata == nil, resetFreshness {
            displayedMetadataFirstSeenAt = nil
            displayedMetadataLastSeenAt = nil
            displayedMetadataReceiptCount = 0
            displayedMetadataHints = []
            displayedMetadataEmbeddedTimestamp = nil
            expiredMetadataThisSession = nil
        }
        if let metadata {
            diagnose("metadata.displayed", "Track metadata displayed", metadata: [
                "album": metadata.album ?? "<none>",
                "artist": metadata.artist,
                "source": source,
                "stationID": station.id,
                "stationName": station.name,
                "title": metadata.title
            ])
        } else if let previous {
            diagnose("metadata.displayCleared", "Track metadata display cleared", metadata: [
                "previousArtist": previous.artist,
                "previousTitle": previous.title,
                "source": source,
                "stationID": station.id,
                "stationName": station.name
            ])
        }
        publishNowPlaying()
    }

    private func expireStaleMetadataIfNeeded(now: Date = Date()) {
        guard requested, !syncEnabled, let metadata = trackMetadata,
              let firstSeenAt = displayedMetadataFirstSeenAt else { return }
        let isMusic = displayedMetadataHints == ["music-candidate"]
        let lifetime = isMusic
            ? metadataFreshnessPolicy.musicDisplayLifetime
            : metadataFreshnessPolicy.nonMusicDisplayLifetime
        guard now.timeIntervalSince(firstSeenAt) >= lifetime else { return }
        recordStaleMetadata(
            metadata,
            evaluation: StreamTrackMetadataEvaluation(
                metadata: metadata,
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                outcome: .accepted,
                classificationHints: displayedMetadataHints
            ),
            source: trackMetadataSource ?? "unknown",
            reason: "unchanged-display-expired",
            now: now,
            onlyOnce: false
        )
        expiredMetadataThisSession = metadata
        applyTrackMetadata(nil, source: "stale-expiry", resetFreshness: false)
    }

    private func recordStaleMetadata(
        _ metadata: StreamTrackMetadata,
        evaluation: StreamTrackMetadataEvaluation,
        source: String,
        reason: String,
        now: Date,
        onlyOnce: Bool
    ) {
        let signature = [station.id, source, reason, metadata.title, metadata.artist].joined(separator: "\u{1f}")
        if onlyOnce || (signature == lastStaleDiagnosticSignature && now.timeIntervalSince(lastStaleDiagnosticAt) < 60) {
            suppressedStaleDiagnosticCount += 1
            return
        }
        if signature != lastStaleDiagnosticSignature { suppressedStaleDiagnosticCount = 0 }
        let formatter = ISO8601DateFormatter()
        var fields = metadataFreshnessPolicy.diagnosticDetails(for: evaluation, at: now)
        if let displayedMetadataEmbeddedTimestamp {
            fields["displayedEmbeddedTimestamp"] = formatter.string(from: displayedMetadataEmbeddedTimestamp)
            fields["displayedEmbeddedTimestampAgeSeconds"] = String(
                format: "%.1f",
                now.timeIntervalSince(displayedMetadataEmbeddedTimestamp)
            )
        }
        fields.merge([
            "artist": metadata.artist,
            "classificationHints": evaluation.classificationHints.joined(separator: ","),
            "displayAgeSeconds": String(format: "%.1f", now.timeIntervalSince(displayedMetadataFirstSeenAt ?? now)),
            "firstSeenAt": displayedMetadataFirstSeenAt.map { formatter.string(from: $0) } ?? "not-displayed-this-session",
            "identicalReceiptCount": "\(max(0, displayedMetadataReceiptCount - 1))",
            "suppressedRepeatedDecisionCount": "\(suppressedStaleDiagnosticCount)",
            "lastSeenAt": displayedMetadataLastSeenAt.map { formatter.string(from: $0) } ?? "not-displayed-this-session",
            "reason": reason,
            "source": source,
            "stationID": station.id,
            "stationName": station.name,
            "title": metadata.title
        ]) { _, new in new }
        diagnose("metadata.stale", "Stale metadata was prevented from remaining on display", metadata: fields)
        lastStaleDiagnosticSignature = signature
        lastStaleDiagnosticAt = now
        suppressedStaleDiagnosticCount = 0
    }
}
