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
    @Published var syncEnabled = UserDefaults.standard.object(forKey: "syncEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "syncEnabled")
            directoryAudio.setSyncEnabled(syncEnabled)
            trackMetadata = nil
            if !syncEnabled { measured = nil }
            updateAudioSessionMode()
            publishNowPlaying()
            diagnose("settings.sync", syncEnabled ? "TV Sync enabled" : "TV Sync disabled", metadata: ["delaySeconds": String(format: "%.1f", delay)])
        }
    }
    @Published var vocalBoost = VocalBoostLevel(
        rawValue: UserDefaults.standard.string(forKey: "vocalBoostLevel") ?? "off"
    ) ?? .off {
        didSet {
            UserDefaults.standard.set(vocalBoost.rawValue, forKey: "vocalBoostLevel")
            directoryAudio.setVocalBoost(vocalBoost)
            trackMetadata = nil
            updateAudioSessionMode()
            publishNowPlaying()
            diagnose("settings.vocalBoost", "Vocal Boost changed", metadata: ["level": vocalBoost.rawValue])
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
    @Published private(set) var supportsDelay = false
    @Published var selectedStreamID = "" { didSet {
        guard oldValue != selectedStreamID else { return }
        if station.playableStreams.contains(where: { $0.id == selectedStreamID }) {
            defaults.set(selectedStreamID, forKey: streamSelectionKey(for: station.id))
        }
        directoryAudio.configure(station, streamID: selectedStreamID)
        if requested { directoryAudio.start() }
    } }
    let library: StationLibrary
    let sleepTimer = SleepTimerService()
    private let directoryAudio = DirectoryAudio()
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
        pause()
        diagnose("station.selected", "Station selected", metadata: ["stationID": value.id])
        station = value; supportsDelay = false; measured = nil; trackMetadata = nil
        resetNowPlayingArtwork()
        selectedStreamID = savedStreamID(for: value) ?? value.preferredStream?.id ?? ""
        directoryAudio.configure(value, streamID: selectedStreamID)
        directoryAudio.setDelay(delay)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "lastPlayedStation.v1") }
        refreshDetails()
        play()
    }
    private func startEngine() { directoryAudio.start() }
    private func reconnectEngine() { directoryAudio.reconnect() }
    private func updateAudioSessionMode() {
        let mode: AVAudioSession.Mode = !syncEnabled && vocalBoost != .off ? .spokenAudio : .default
        try? AVAudioSession.sharedInstance().setMode(mode)
    }
    @Published private(set) var requested = false
    @Published private(set) var status = "Ready to play"
    @Published private(set) var detail = "Choose a station in Discover"
    @Published private(set) var buffering = false
    @Published private(set) var progress = 0.0
    @Published private(set) var measured: Double?
    @Published private(set) var route = "This device"
    let guide = ProgrammeGuide()
    private let monitor = NWPathMonitor()
    private var subscriptions = Set<AnyCancellable>()
    private var resumeAfterInterruption = false
    private var hadConnection = true
    private var isForeground = true
    private var lastMetadata = ""
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

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            self.buffering = update.buffering; self.progress = update.progress; self.measured = update.measuredDelay
            self.supportsDelay = supported; self.updateRecoveryGrace(); self.publishNowPlaying()
        }
        directoryAudio.onTrackMetadata = { [weak self] metadata in
            guard let self else { return }
            self.trackMetadata = self.syncEnabled ? nil : metadata
            self.publishNowPlaying()
        }
        directoryAudio.setSyncEnabled(syncEnabled)
        directoryAudio.setVocalBoost(vocalBoost)
        directoryAudio.setDelay(delay)
        sleepTimer.onFadeVolume = { [weak self] volume in
            self?.directoryAudio.setVolume(volume)
        }
        sleepTimer.onPause = { [weak self] in
            guard let self, self.requested else { return }
            self.pause()
        }
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

    func play() {
        diagnose("player.play", "Play requested", metadata: ["stationID": station.id, "streamID": selectedStreamID])
        if !sleepTimer.checkAutoRestart() {
            sleepTimer.restoreFullVolume()
        }
        let token = UUID()
        activationID = token
        requested = true
        resumeAfterInterruption = false
        status = "Connecting…"
        do {
            let session = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = !syncEnabled && vocalBoost != .off ? .spokenAudio : .default
            try session.setCategory(.playback, mode: mode, policy: .longFormAudio, options: [])
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
        endRecoveryGrace()
        resumeAfterInterruption = false
        directoryAudio.stop()
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

    func toggle() { requested ? pause() : play() }
    func adjust(_ amount: Double) { delay = min(30, max(0, delay + amount)) }
    func sceneChanged(_ phase: ScenePhase) {
        diagnose("app.scene", "Scene phase changed", metadata: ["phase": String(describing: phase), "playing": "\(requested)", "buffering": "\(buffering)"])
        isForeground = phase == .active
        if isForeground { recoveryGraceUsed = false; endRecoveryGrace() }
        if phase == .active {
            refreshRoute()
            refreshDetails()
            publishNowPlaying()
        }
    }

    private func recordPlaybackStatus(_ update: PlaybackStatus, supportsDelay: Bool) {
        let statusKey = "\(update.active)|\(update.buffering)|\(update.title)|\(supportsDelay)"
        if update.buffering, bufferingStartedAt == nil { bufferingStartedAt = Date() }
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
    private func registerRemoteControls() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        centre.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        for command in [centre.nextTrackCommand, centre.previousTrackCommand, centre.skipForwardCommand,
                        centre.skipBackwardCommand, centre.changePlaybackPositionCommand, centre.changePlaybackRateCommand] {
            command.isEnabled = false
        }
    }
    private func publishNowPlaying() {
        let metadata = syncEnabled ? nil : trackMetadata
        let title = metadata?.title ?? displayTitle
        let artist = metadata?.artist ?? station.name
        let audible = requested && status == "Playing"
        requestNowPlayingArtworkIfNeeded()
        let key = "\(station.id)|\(title)|\(artist)|\(metadata?.album ?? "")|\(audible)|\(nowPlayingArtwork != nil)"
        guard key != lastMetadata else { return }
        lastMetadata = key
        var information: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: metadata?.album ?? station.name,
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
        else { guide.stop() }
    }
}
