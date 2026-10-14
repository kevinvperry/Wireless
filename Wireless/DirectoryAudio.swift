import Foundation
import AVFoundation

struct StreamTrackMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
}

private final class StreamMetadataOutputDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    var receive: (@Sendable (StreamTrackMetadata?) -> Void)?

    private final class ItemsBox: @unchecked Sendable {
        let items: [AVMetadataItem]
        init(_ items: [AVMetadataItem]) { self.items = items }
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let box = ItemsBox(groups.flatMap(\.items))
        let callback = receive
        Task {
            callback?(await StreamTrackMetadataParser.parse(box.items))
        }
    }
}

private enum StreamTrackMetadataParser {
    static func parse(_ items: [AVMetadataItem]) async -> StreamTrackMetadata? {
        var title: String?
        var artist: String?
        var album: String?

        for item in items {
            guard let loaded = try? await item.load(.stringValue),
                  let value = clean(loaded) else { continue }
            switch item.commonKey {
            case .commonKeyTitle: title = value
            case .commonKeyArtist: artist = value
            case .commonKeyAlbumName: album = value
            default:
                if item.identifier == .icyMetadataStreamTitle { title = value }
            }
        }

        if artist == nil, let combined = title, let split = splitCombinedTitle(combined) {
            artist = split.artist
            title = split.title
        }
        guard let acceptedTitle = acceptable(title), let acceptedArtist = acceptable(artist) else { return nil }
        return StreamTrackMetadata(title: acceptedTitle, artist: acceptedArtist, album: acceptable(album))
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func splitCombinedTitle(_ value: String) -> (artist: String, title: String)? {
        for separator in [" - ", " – ", " — "] {
            let parts = value.components(separatedBy: separator)
            guard parts.count >= 2,
                  let artist = clean(parts.first),
                  let title = clean(parts.dropFirst().joined(separator: separator)) else { continue }
            return (artist, title)
        }
        return nil
    }

    private static func acceptable(_ value: String?) -> String? {
        guard let value = clean(value), value.count >= 2, value.count <= 180 else { return nil }
        let lower = value.lowercased()
        let rejectedPhrases = [
            "advertisement", "commercial break", "station identification", "station id",
            "you are listening", "you're listening", "listen live", "more music",
            "non-stop music", "non stop music", "sponsored by", "traffic update",
            "news update", "now playing"
        ]
        guard !rejectedPhrases.contains(where: lower.contains),
              !lower.hasPrefix("http://"), !lower.hasPrefix("https://"),
              lower.range(of: #"^[\W_]+$"#, options: .regularExpression) == nil else { return nil }
        return value
    }
}

/// Uses AVPlayer for ordinary live listening. Sync mode keeps Wireless's packet
/// history for direct MP3/AAC streams and as a fallback for HLS feeds that do
/// not expose a seekable live window through AVFoundation.
/// All AVPlayer state and item replacement are confined to the main actor.
@MainActor final class DirectoryAudio {
    var onStatus: ((PlaybackStatus, Bool) -> Void)?
    var onTrackMetadata: ((StreamTrackMetadata?) -> Void)?
    private let player = AVPlayer()
    private let packetEngine = RadioStreamEngine()
    private let enhancedEngine = EnhancedLiveStreamEngine()
    private let metadataDelegate = StreamMetadataOutputDelegate()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var usesPacketBuffer = false
    private var usesEnhancedPlayback = false
    private var hlsPacketFallbackAttempted = false
    private var itemObservers: [NSObjectProtocol] = []
    private var itemStatusObservation: NSKeyValueObservation?

    init() {
        metadataDelegate.receive = { [weak self] metadata in
            Task { @MainActor in
                guard let self, self.requested, !self.syncEnabled, !self.usesPacketBuffer else { return }
                self.onTrackMetadata?(metadata)
            }
        }
        packetEngine.onStatus = { [weak self] update in
            Task { @MainActor in
                guard let self, self.requested, self.usesPacketBuffer else { return }
                if update.title == "Playing" { self.lastAdvance = Date() }
                self.onStatus?(PlaybackStatus(active: self.requested, buffering: update.buffering, progress: update.progress, title: update.title, detail: update.detail, measuredDelay: update.measuredDelay), true)
            }
        }
        enhancedEngine.onStatus = { [weak self] update in
            Task { @MainActor in
                guard let self, self.requested, self.usesEnhancedPlayback else { return }
                if update.title == "Playing" { self.lastAdvance = Date() }
                self.onStatus?(update, false)
            }
        }
    }
    private var streams: [StationStream] = []
    private var index = 0
    private var requested = false
    private var timer: Timer?
    private var started = Date()
    private var lastAdvance = Date()
    private var lastTime = -1.0
    private var delay = 0.0
    private var syncEnabled = true
    private var vocalBoost: VocalBoostLevel = .off
    private var pendingDelay = true
    private var generation = UUID()
    private var seeking = false
    private var failure = ""
    private(set) var selectedStreamID: String?

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }

    func configure(_ station: DirectoryStation, streamID: String? = nil) {
        stop()
        onTrackMetadata?(nil)
        let preferred = station.playableStreams.first { $0.id == streamID } ?? station.preferredStream
        streams = preferred.map { first in [first] + station.playableStreams.filter { $0.id != first.id } } ?? []
        index = 0; selectedStreamID = streams.first?.id
        diagnose("stream.configure", "Configured station streams", metadata: [
            "stationID": station.id,
            "requestedStreamID": streamID ?? "automatic",
            "candidateCount": "\(streams.count)"
        ])
    }
    func start() {
        guard !streams.isEmpty else { emitFailure("This station has no compatible stream."); return }
        guard !requested else { return }
        requested = true; failure = ""; index = 0
        diagnose("playback.start", "Playback requested")
        load()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func reconnect() {
        guard requested, !streams.isEmpty else { return }
        failure = ""
        diagnose("playback.reconnect", "Reconnect requested")
        load()
    }
    func stop() {
        if requested { diagnose("playback.stop", "Playback stopped") }
        requested = false; generation = UUID(); seeking = false
        timer?.invalidate(); timer = nil
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        packetEngine.stop(); packetEngine.suspendPreparation()
        enhancedEngine.stop()
    }
    func setSyncEnabled(_ enabled: Bool) {
        guard syncEnabled != enabled else { return }
        syncEnabled = enabled
        diagnose("sync.mode", enabled ? "TV Sync enabled" : "TV Sync disabled", metadata: ["delaySeconds": String(format: "%.1f", delay)])
        onTrackMetadata?(nil)
        packetEngine.setSyncEnabled(enabled)
        generation = UUID()
        player.currentItem?.cancelPendingSeeks()
        seeking = false
        pendingDelay = enabled
        player.automaticallyWaitsToMinimizeStalling = true
        player.currentItem?.preferredForwardBufferDuration = 5
        // The playback backend is a mode decision: ordinary listening always
        // returns to AVPlayer, while Sync may need Wireless's retained packets.
        if requested { load() }
    }
    func setVocalBoost(_ level: VocalBoostLevel) {
        guard vocalBoost != level else { return }
        vocalBoost = level
        onTrackMetadata?(nil)
        if requested { load() }
    }
    func setDelay(_ value: Double) {
        let materiallyChanged = abs(delay - value) >= 0.49
        delay = value; packetEngine.setDelay(value); pendingDelay = true; applyDelay()
        if materiallyChanged { diagnose("sync.delay", "Selected delay changed", metadata: ["seconds": String(format: "%.1f", value)]) }
    }
    func setVolume(_ value: Float) {
        let volume = min(1, max(0, value))
        player.volume = volume
        packetEngine.setVolume(volume)
        enhancedEngine.setVolume(volume)
    }
    private func load() {
        guard requested, streams.indices.contains(index), let url = streams[index].playableURL else { return }
        onTrackMetadata?(nil)
        generation = UUID(); seeking = false; selectedStreamID = streams[index].id
        packetEngine.stop(); packetEngine.suspendPreparation()
        enhancedEngine.stop()
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        let stream = streams[index]
        usesPacketBuffer = syncEnabled && stream.format != "hls" && stream.supportsPacketBuffer
        usesEnhancedPlayback = !syncEnabled && vocalBoost != .off && ["mp3", "aac"].contains(stream.format)
        hlsPacketFallbackAttempted = false
        started = Date(); lastAdvance = started; lastTime = -1; pendingDelay = true
        let backend = usesPacketBuffer ? "packet-buffer" : (usesEnhancedPlayback ? "audio-engine" : "avplayer")
        diagnose("stream.load", "Loading stream", metadata: [
            "streamID": stream.id,
            "url": stream.url,
            "format": stream.format,
            "codec": stream.codec,
            "bitrateKbps": stream.bitrate_kbps.map { String(format: "%.0f", $0) } ?? "unknown",
            "backend": backend,
            "syncEnabled": "\(syncEnabled)",
            "vocalBoost": vocalBoost.rawValue
        ])
        if usesPacketBuffer {
            packetEngine.selectBufferedStream(stream); packetEngine.setDelay(delay); packetEngine.start()
            return
        }
        if usesEnhancedPlayback {
            enhancedEngine.configure(stream: stream, level: vocalBoost)
            enhancedEngine.start()
            publish(title: "Connecting…", detail: "Preparing Vocal Boost", buffering: true, supportsDelay: false)
            return
        }
        var options: [String: Any] = [:]
        if let agent = streams[index].request_headers.first(where: { $0.key.lowercased() == "user-agent" })?.value { options[AVURLAssetHTTPUserAgentKey] = agent }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        if !syncEnabled {
            let output = AVPlayerItemMetadataOutput(identifiers: nil)
            output.setDelegate(metadataDelegate, queue: .main)
            item.add(output)
            metadataOutput = output
        }
        item.preferredForwardBufferDuration = 5
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        installItemObservers(item, token: generation)
        started = Date(); lastAdvance = started; lastTime = -1; pendingDelay = true
        player.play()
        publish(title: "Connecting…", detail: "\(streams[index].format.uppercased()) · \(streams[index].label)", buffering: true, supportsDelay: false)
    }
    private var seekRange: CMTimeRange? {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue,
              range.duration.seconds.isFinite, range.duration.seconds > 3 else { return nil }
        return range
    }
    private func applyDelay() {
        guard syncEnabled, !usesPacketBuffer, pendingDelay, !seeking, requested, let range = seekRange else { return }
        pendingDelay = false; seeking = true
        let token = generation
        let end = CMTimeRangeGetEnd(range).seconds
        let target = max(range.start.seconds, end - max(2.5, delay))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.seeking = false; self.lastAdvance = Date()
                if self.requested { self.player.play() }
            }
        }
    }
    private func tick() {
        guard requested else { return }
        if usesPacketBuffer {
            if Date().timeIntervalSince(lastAdvance) > max(45, delay + 25) { nextStream() }
            return
        }
        guard let item = player.currentItem else { return }
        let time = player.currentTime().seconds
        if time.isFinite, abs(time - lastTime) > 0.05 { lastAdvance = Date(); lastTime = time }
        if item.status == .failed || Date().timeIntervalSince(lastAdvance) > 25 {
            diagnose("stream.stalled", "Stream stopped advancing", metadata: [
                "streamID": selectedStreamID ?? "unknown",
                "elapsedSeconds": String(format: "%.1f", Date().timeIntervalSince(lastAdvance))
            ])
            nextStream()
            return
        }
        if syncEnabled,
           streams[index].format == "hls",
           streams[index].supportsPacketBuffer,
           seekRange == nil,
           !hlsPacketFallbackAttempted,
           Date().timeIntervalSince(started) >= 8 {
            switchHLSIntoPacketFallback()
            return
        }
        applyDelay()
        let playing = player.timeControlStatus == .playing && !seeking
        let supported = seekRange != nil
        let detail = !syncEnabled ? "Live playback · stream buffer managed automatically." : supported ? "Delay is measured from this stream’s available live edge." : "Live playback. This stream does not provide a seekable delay buffer."
        publish(title: playing ? "Playing" : "Buffering…", detail: detail, buffering: !playing, supportsDelay: supported)
    }
    private func nextStream() {
        if index + 1 < streams.count {
            let previous = streams[index].id
            index += 1
            diagnose("stream.failover", "Trying alternate stream", metadata: ["fromStreamID": previous, "toStreamID": streams[index].id])
            load()
        }
        else { emitFailure("Couldn’t play this station. Check your connection or try another station.") }
    }
    private func switchHLSIntoPacketFallback() {
        guard requested, streams.indices.contains(index) else { return }
        hlsPacketFallbackAttempted = true
        generation = UUID(); seeking = false
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        usesPacketBuffer = true
        diagnose("sync.hlsFallback", "HLS has no seekable window; switching to retained packet buffer", metadata: ["streamID": streams[index].id, "url": streams[index].url])
        started = Date(); lastAdvance = started; lastTime = -1
        packetEngine.selectBufferedStream(streams[index])
        packetEngine.setDelay(delay)
        packetEngine.start()
    }
    private func installItemObservers(_ item: AVPlayerItem, token: UUID) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.generation == token, self.player.currentItem === item else { return }
                if item.status == .failed { self.nextStream() }
            }
        }
        itemObservers = [
            NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item else { return }
                    self.diagnose("stream.playbackStalled", "AVPlayer reported a playback stall", metadata: ["streamID": self.selectedStreamID ?? "unknown"])
                    self.publish(title: "Buffering…", detail: "Waiting for enough stream data.", buffering: true, supportsDelay: self.seekRange != nil)
                    self.player.play()
                }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item else { return }
                    self.nextStream()
                }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item else { return }
                    self.nextStream()
                }
            }
        ]
    }
    private func removeItemObservers() {
        metadataOutput?.setDelegate(nil, queue: nil)
        metadataOutput = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers.removeAll()
    }

    private func emitFailure(_ message: String) {
        diagnose("stream.unavailable", message, metadata: ["streamID": selectedStreamID ?? "unknown"])
        stop(); failure = message
        onStatus?(PlaybackStatus(active: false, buffering: false, progress: 0, title: "Station unavailable", detail: message, measuredDelay: nil), false)
    }
    private func publish(title: String, detail: String, buffering: Bool, supportsDelay: Bool) {
        let measured = seekRange.flatMap { range -> Double? in
            let value = CMTimeRangeGetEnd(range).seconds - player.currentTime().seconds
            return value.isFinite ? max(0, value) : nil
        }
        onStatus?(PlaybackStatus(active: requested, buffering: buffering, progress: buffering ? 0 : 1, title: title, detail: detail, measuredDelay: syncEnabled ? measured : nil), supportsDelay)
    }
}
