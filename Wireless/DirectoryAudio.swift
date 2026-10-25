import Foundation
import AVFoundation

private final class StreamMetadataOutputDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    var receive: (@Sendable (StreamTrackMetadataEvaluation) -> Void)?

    func cancelPendingMetadata() {
        receive = nil
    }

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
            let evaluation = await StreamTrackMetadataParser.evaluate(box.items)
            callback?(evaluation)
        }
    }
}

/// Uses AVPlayer for ordinary live listening. Sync mode keeps Wireless's packet
/// history for direct MP3/AAC streams and as a fallback for HLS feeds that do
/// not expose a seekable live window through AVFoundation.
/// All AVPlayer state and item replacement are confined to the main actor.
@MainActor final class DirectoryAudio {
    var onStatus: ((PlaybackStatus, Bool) -> Void)?
    var onAudioEffectState: ((VocalBoostState) -> Void)?
    private(set) var audioEffectState: VocalBoostState = .off
    private var hlsVocalBoostTap: HLSVocalBoostTap?
    private var lastProcessedFrames: Int64 = 0
    private var lastProcessedAt = Date.distantPast
    var onTrackMetadata: ((StreamTrackMetadataEvaluation?) -> Void)?
    var onPlaybackInterval: ((TimeInterval, Date) -> Void)?
    private let player = AVPlayer()
    private let metadataSidecarPlayer = AVPlayer()
    private let packetEngine = RadioStreamEngine()
    private let enhancedEngine = EnhancedLiveStreamEngine()
    private let metadataDelegate = StreamMetadataOutputDelegate()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataSidecarOutput: AVPlayerItemMetadataOutput?
    private var usesPacketBuffer = false
    private var usesEnhancedPlayback = false
    private var hlsPacketFallbackAttempted = false
    private var hlsBoostFallbackAttempted = false
    private var hlsBoostFailure: String?
    private var itemObservers: [NSObjectProtocol] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private var lastMetadataEvaluation: StreamTrackMetadataEvaluation?
    private var lastEmbeddedMetadata: StreamTrackMetadata?
    private var embeddedMetadataReceiptNumber = 0
    private let metadataHeartbeatInterval: TimeInterval
    private let metadataSilenceWarningInterval: TimeInterval
    private let metadataFreshnessPolicy = MetadataFreshnessPolicy()
    private var metadataTimeline: MetadataDiagnosticTimeline?
    private var stationID = "unknown"
    private var stationName = "Unknown station"
    private var companionMetadataPreferred = false
    private var avPlayerAccountingSample: (position: TimeInterval, uptime: TimeInterval)?

    init(metadataHeartbeatInterval: TimeInterval = 60, metadataSilenceWarningInterval: TimeInterval = 120) {
        self.metadataHeartbeatInterval = metadataHeartbeatInterval
        self.metadataSilenceWarningInterval = metadataSilenceWarningInterval
        packetEngine.onStatus = { [weak self] update in
            Task { @MainActor in
                guard let self, self.requested, self.usesPacketBuffer else { return }
                if update.title == "Playing" { self.lastAdvance = Date(); self.recovery.recordPlayback(at: Date()) }
                self.onStatus?(PlaybackStatus(active: self.requested, buffering: update.buffering, progress: update.progress, title: update.title, detail: update.detail, measuredDelay: update.measuredDelay), true)
            }
        }
        packetEngine.onPlaybackInterval = { [weak self] seconds, endedAt in
            Task { @MainActor in
                guard let self, self.requested, self.usesPacketBuffer else { return }
                self.onPlaybackInterval?(seconds, endedAt)
            }
        }
        enhancedEngine.onUnsupportedHLS = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.requested, self.usesEnhancedPlayback,
                      self.streams.indices.contains(self.index), self.streams[self.index].format == "hls" else { return }
                self.hlsBoostFailure = reason
                self.load(preservingVocalBoostFallback: true)
            }
        }
        enhancedEngine.onStatus = { [weak self] update in
            Task { @MainActor in
                guard let self, self.requested, self.usesEnhancedPlayback else { return }
                if update.buffering { self.setAudioEffectState(.preparing) }
                if update.title == "Playing" { self.lastAdvance = Date(); self.recovery.recordPlayback(at: Date()) }
                self.onStatus?(PlaybackStatus(active: self.requested, buffering: update.buffering, progress: update.progress, title: update.title, detail: update.detail, measuredDelay: update.measuredDelay), false)
            }
        }
        enhancedEngine.onPlaybackInterval = { [weak self] seconds, endedAt in
            Task { @MainActor in
                guard let self, self.requested, self.usesEnhancedPlayback else { return }
                self.lastAdvance = Date()
                self.recovery.recordPlayback(at: Date())
                self.setAudioEffectState(.active)
                self.onPlaybackInterval?(seconds, endedAt)
            }
        }
    }
    private var streams: [StationStream] = []
    private var index = 0
    private var requested = false
    private var preparing = false
    private var prerollStarted = false
    private var retryAt: Date?
    private var recovery = StreamRecoveryPolicy()
    private var timer: Timer?
    private var started = Date()
    private var lastAdvance = Date()
    private var lastTime = -1.0
    private var delay = 0.0
    private var syncEnabled = true
    private var vocalBoost: VocalBoostLevel = .off
    private var deepBass = false
    private var soundControlsEnabled: Bool { vocalBoost != .off || deepBass }
    private var effectName: String { deepBass ? "Deep Bass" : "Vocal Boost" }
    private var pendingDelay = true
    private var generation = UUID()
    private var seeking = false
    private var failure = ""
    private(set) var selectedStreamID: String?

    private func setAudioEffectState(_ state: VocalBoostState) {
        guard audioEffectState != state else { return }
        audioEffectState = state
        onAudioEffectState?(state)
        diagnose("vocalBoost.state", state.message(for: effectName), metadata: [
            "streamID": selectedStreamID ?? "unknown",
            "tapPrepareCount": "\(hlsVocalBoostTap?.state.prepareCount.load(ordering: .relaxed) ?? 0)",
            "tapFrames": "\(hlsVocalBoostTap?.state.processedFrames.load(ordering: .relaxed) ?? 0)"
        ])
    }

    private func updateAudioEffectState() {
        if syncEnabled { setAudioEffectState(.suspendedForSync); return }
        if !soundControlsEnabled { setAudioEffectState(.off); return }
        let supportsHLSTap: Bool
        if #available(iOS 27.0, *) { supportsHLSTap = true } else { supportsHLSTap = false }
        let format = streams.indices.contains(index) ? streams[index].format : nil
        if let reason = VocalBoostState.unsupportedReason(format: format, supportsHLSTap: supportsHLSTap, effect: effectName) {
            setAudioEffectState(.unavailable(reason)); return
        }
        guard requested else { setAudioEffectState(.ready); return }
        if usesEnhancedPlayback {
            if Date().timeIntervalSince(lastAdvance) > 2 || !audioEffectState.isActive { setAudioEffectState(.preparing) }
            return
        }
        if let hlsBoostFailure { setAudioEffectState(.unavailable(hlsBoostFailure)); return }
        guard let tap = hlsVocalBoostTap else {
            setAudioEffectState(.unavailable("The HLS audio processor could not start.")); return
        }
        let failure = tap.state.failure.load(ordering: .relaxed)
        if failure != noErr {
            setAudioEffectState(.unavailable("Audio processing failed for this stream (\(failure)).")); return
        }
        let frames = tap.state.processedFrames.load(ordering: .relaxed)
        if frames == 0 { lastProcessedAt = .distantPast }
        if frames > 0, frames != lastProcessedFrames {
            lastProcessedFrames = frames
            lastProcessedAt = Date()
        }
        if player.timeControlStatus == .playing, Date().timeIntervalSince(lastProcessedAt) < 2 {
            setAudioEffectState(.active)
        } else if player.timeControlStatus == .playing, Date().timeIntervalSince(started) > 10 {
            setAudioEffectState(.unavailable("This stream or audio route does not allow sound processing."))
        } else { setAudioEffectState(.preparing) }
    }

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }

    func configure(_ station: DirectoryStation, streamID: String? = nil) {
        stop()
        stationID = station.id
        stationName = station.name
        onTrackMetadata?(nil)
        let preferred = station.playableStreams.first { $0.id == streamID } ?? station.preferredStream
        streams = preferred.map { first in [first] + station.playableStreams.filter { $0.id != first.id } } ?? []
        index = 0; selectedStreamID = streams.first?.id
        diagnose("stream.configure", "Configured station streams", metadata: [
            "stationID": station.id,
            "stationName": station.name,
            "requestedStreamID": streamID ?? "automatic",
            "candidateCount": "\(streams.count)"
        ])
        prepare()
    }

    /// Adapted from Autohop’s paused-player preload; reuse the same backend on Play.
    func prepare() {
        guard !requested, !preparing, !streams.isEmpty else { return }
        preparing = true
        load()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    func start() {
        guard !streams.isEmpty else { emitFailure("This station has no compatible stream."); return }
        guard !requested else { return }
        let wasPrepared = preparing && Date().timeIntervalSince(started) < 60
        requested = true; preparing = false; failure = ""
        recovery.reset(); retryAt = nil
        diagnose("playback.start", "Playback requested", metadata: ["reusedPreparation": "\(wasPrepared)"])
        if wasPrepared {
            started = Date(); lastAdvance = started
            if usesPacketBuffer { packetEngine.start() }
            else if usesEnhancedPlayback {
                enhancedEngine.start()
                if let url = StreamRequestPolicy.playbackURL(for: streams[index]) {
                    startMetadataSidecar(url: url, stream: streams[index], token: generation)
                }
            } else if player.currentItem?.status != .failed {
                player.cancelPendingPrerolls()
                // A paused live window can move on while the user reads the player.
                if !syncEnabled, let range = seekRange,
                   CMTimeRangeGetEnd(range).seconds - player.currentTime().seconds > 10 {
                    player.seek(to: CMTime(seconds: max(range.start.seconds, CMTimeRangeGetEnd(range).seconds - 5), preferredTimescale: 600))
                }
                player.play()
            } else { load() }
        } else { index = 0; load() }
        startTimer()
    }
    func reconnect() {
        guard requested, !streams.isEmpty else { return }
        failure = ""; retryAt = nil
        diagnose("playback.reconnect", "Reconnect requested")
        load()
    }
    func stop() {
        if requested { diagnose("playback.stop", "Playback stopped") }
        requested = false; preparing = false; retryAt = nil; recovery.reset(); generation = UUID(); seeking = false
        timer?.invalidate(); timer = nil
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        hlsVocalBoostTap = nil
        lastProcessedFrames = 0; lastProcessedAt = .distantPast
        updateAudioEffectState()
        stopMetadataSidecar()
        packetEngine.stop(); packetEngine.suspendPreparation()
        enhancedEngine.stop()
        avPlayerAccountingSample = nil
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
        if requested || preparing { load() }
        else { updateAudioEffectState() }
    }
    func setSoundControls(_ level: VocalBoostLevel, deepBass: Bool) {
        guard vocalBoost != level || self.deepBass != deepBass else { return }
        vocalBoost = level
        self.deepBass = deepBass
        if !syncEnabled, usesEnhancedPlayback, soundControlsEnabled, requested || preparing {
            enhancedEngine.setLevel(level, deepBass: deepBass)
            return
        }
        onTrackMetadata?(nil)
        if requested || preparing { load() }
        else { updateAudioEffectState() }
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
    func setCompanionMetadataPreferred(_ preferred: Bool) {
        companionMetadataPreferred = preferred
    }
    private func load(preservingVocalBoostFallback: Bool = false) {
        guard requested || preparing, streams.indices.contains(index),
              let url = StreamRequestPolicy.playbackURL(for: streams[index]) else { return }
        if !preservingVocalBoostFallback { hlsBoostFallbackAttempted = false; hlsBoostFailure = nil }
        onTrackMetadata?(nil)
        generation = UUID(); seeking = false; prerollStarted = false; selectedStreamID = streams[index].id
        avPlayerAccountingSample = nil
        packetEngine.stop(); packetEngine.suspendPreparation()
        enhancedEngine.stop()
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        hlsVocalBoostTap = nil
        lastProcessedFrames = 0; lastProcessedAt = .distantPast
        setAudioEffectState(!soundControlsEnabled ? .off : syncEnabled ? .suspendedForSync : .preparing)
        stopMetadataSidecar()
        let stream = streams[index]
        usesPacketBuffer = syncEnabled && stream.format != "hls" && stream.supportsPacketBuffer
        usesEnhancedPlayback = !syncEnabled && soundControlsEnabled && ["mp3", "aac"].contains(stream.format)
        hlsPacketFallbackAttempted = false
        started = Date(); lastAdvance = started; lastTime = -1; pendingDelay = true
        if usesEnhancedPlayback { updateAudioEffectState() }
        let backend = usesPacketBuffer ? "packet-buffer" : (usesEnhancedPlayback ? "audio-engine" : "avplayer")
        diagnose("stream.load", "Loading stream", metadata: [
            "streamID": stream.id,
            "url": stream.url,
            "format": stream.format,
            "codec": stream.codec,
            "bitrateKbps": stream.bitrate_kbps.map { String(format: "%.0f", $0) } ?? "unknown",
            "backend": backend,
            "cacheStrategy": url == stream.playableURL ? "stream-default" : "sca-per-session-url",
            "syncEnabled": "\(syncEnabled)",
            "vocalBoost": vocalBoost.rawValue,
            "deepBass": "\(deepBass)"
        ])
        if usesPacketBuffer {
            packetEngine.selectBufferedStream(stream); packetEngine.setDelay(delay)
            if requested { packetEngine.start() }
            return
        }
        if usesEnhancedPlayback {
            enhancedEngine.configure(stream: stream, level: vocalBoost, deepBass: deepBass)
            if requested {
                enhancedEngine.start()
                startMetadataSidecar(url: url, stream: stream, token: generation)
            } else { enhancedEngine.prepare() }
            publish(title: "Connecting…", detail: "Preparing \(effectName)", buffering: true, supportsDelay: false)
            return
        }
        var options: [String: Any] = [:]
        if let agent = streams[index].request_headers.first(where: { $0.key.lowercased() == "user-agent" })?.value { options[AVURLAssetHTTPUserAgentKey] = agent }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        if !syncEnabled, soundControlsEnabled, stream.format == "hls", hlsBoostFailure == nil {
            if #available(iOS 27.0, *) {
                do {
                    let tap = try HLSVocalBoostTap(level: vocalBoost, deepBass: deepBass)
                    hlsVocalBoostTap = tap
                } catch {
                    setAudioEffectState(.unavailable("The HLS audio processor could not start."))
                    diagnose("vocalBoost.failed", "Could not create HLS processing tap", metadata: ["error": "\(error)"])
                }
            }
        }
        if !syncEnabled {
            configureMetadataReceiver(token: generation, transport: "avplayer-timed-metadata")
            let output = AVPlayerItemMetadataOutput(identifiers: nil)
            output.setDelegate(metadataDelegate, queue: .main)
            item.add(output)
            metadataOutput = output
        }
        item.preferredForwardBufferDuration = 5
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        if #available(iOS 27.0, *), let hlsVocalBoostTap, let current = player.currentItem {
            hlsVocalBoostTap.attach(to: current)
        }
        updateAudioEffectState()
        installItemObservers(item, token: generation)
        started = Date(); lastAdvance = started; lastTime = -1; pendingDelay = true
        if requested { player.play() }
        publish(title: requested ? "Connecting…" : "Preparing audio…", detail: "\(streams[index].format.uppercased()) · \(streams[index].label)", buffering: true, supportsDelay: false)
    }

    private func configureMetadataReceiver(token: UUID, transport: String) {
        metadataTimeline = MetadataDiagnosticTimeline(
            heartbeatInterval: metadataHeartbeatInterval,
            silenceWarningInterval: metadataSilenceWarningInterval
        )
        metadataDelegate.receive = { [weak self] evaluation in
            Task { @MainActor in
                guard let self, self.generation == token, self.requested,
                      !self.syncEnabled, !self.usesPacketBuffer else { return }
                let now = Date()
                let evaluation = evaluation.addingProviderDetails(
                    self.metadataFreshnessPolicy.diagnosticDetails(for: evaluation, at: now)
                )
                var elapsed: [String: String] = [:]
                if var timeline = self.metadataTimeline {
                    elapsed = timeline.record(evaluation, at: now)
                    self.metadataTimeline = timeline
                }
                self.embeddedMetadataReceiptNumber += 1
                let repeated = evaluation.hasSameCandidate(as: self.lastMetadataEvaluation)
                let trackChanged = evaluation.metadata != nil && evaluation.metadata != self.lastEmbeddedMetadata
                self.lastMetadataEvaluation = evaluation
                var fields = evaluation.diagnosticFields
                fields.merge(elapsed) { _, new in new }
                fields["source"] = "embedded"
                fields["streamID"] = self.selectedStreamID ?? "unknown"
                fields["stationID"] = self.stationID
                fields["stationName"] = self.stationName
                fields["receiptNumber"] = "\(self.embeddedMetadataReceiptNumber)"
                fields["repeatedEvaluation"] = "\(repeated)"
                fields["acceptedTrackChanged"] = "\(trackChanged)"
                fields["transport"] = transport
                self.diagnose("metadata.evaluated", "Embedded stream metadata received and evaluated", metadata: fields)
                if let metadata = evaluation.metadata { self.lastEmbeddedMetadata = metadata }
                self.onTrackMetadata?(evaluation)
            }
        }
    }

    private func startMetadataSidecar(url: URL, stream: StationStream, token: UUID) {
        configureMetadataReceiver(token: token, transport: "avplayer-muted-sidecar")
        var options: [String: Any] = [:]
        if let agent = stream.request_headers.first(where: { $0.key.lowercased() == "user-agent" })?.value {
            options[AVURLAssetHTTPUserAgentKey] = agent
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(metadataDelegate, queue: .main)
        item.add(output)
        metadataSidecarOutput = output
        metadataOutput = output
        metadataSidecarPlayer.volume = 0
        metadataSidecarPlayer.replaceCurrentItem(with: item)
        metadataSidecarPlayer.play()
        diagnose("metadata.providerStarted", "Muted embedded metadata sidecar started", metadata: [
            "stationID": stationID,
            "stationName": stationName,
            "streamID": stream.id,
            "transport": "avplayer-muted-sidecar",
            "reason": "audio-engine-does-not-expose-timed-metadata"
        ])
    }

    private func stopMetadataSidecar() {
        metadataSidecarPlayer.pause()
        metadataSidecarPlayer.replaceCurrentItem(with: nil)
        metadataSidecarOutput = nil
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
                self.avPlayerAccountingSample = nil
                if self.requested { self.player.play() }
            }
        }
    }
    private func tick() {
        if preparing {
            if !usesPacketBuffer, !usesEnhancedPlayback, !prerollStarted,
               player.status == .readyToPlay, player.currentItem?.status == .readyToPlay,
               player.rate == 0 {
                prerollStarted = true
                let token = generation
                player.preroll(atRate: 1) { [weak self] ready in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.preparing else { return }
                        self.diagnose("stream.prepared", "Silent audio preparation completed", metadata: ["ready": "\(ready)"])
                    }
                }
            }
            // Bound unattended mobile-data use. Opening the player again can prepare anew.
            if Date().timeIntervalSince(started) >= 60 {
                stop()
                publish(title: "Ready to play", detail: "Press Play to connect to the live broadcast.", buffering: false, supportsDelay: false)
            }
            return
        }
        guard requested else { return }
        if let retryAt {
            if Date() >= retryAt { self.retryAt = nil; load() }
            return
        }
        updateAudioEffectState()
        if #available(iOS 27.0, *), !syncEnabled, soundControlsEnabled, !usesEnhancedPlayback,
           streams.indices.contains(index), streams[index].format == "hls",
           !hlsBoostFallbackAttempted,
           !audioEffectState.isActive, player.timeControlStatus == .playing,
           Date().timeIntervalSince(started) > 10 {
            switchHLSIntoVocalBoostFallback()
            return
        }
        checkMetadataDiagnostics()
        if usesPacketBuffer || usesEnhancedPlayback {
            if Date().timeIntervalSince(lastAdvance) > max(20, syncEnabled ? delay + 15 : 20) { nextStream() }
            return
        }
        guard let item = player.currentItem else { return }
        let time = player.currentTime().seconds
        if player.timeControlStatus == .playing, time.isFinite, abs(time - lastTime) > 0.05 {
            lastAdvance = Date(); lastTime = time
            recovery.recordPlayback(at: Date())
        }
        if item.status == .failed || Date().timeIntervalSince(lastAdvance) > 12 {
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
        recordAVPlayerInterval(position: time, playing: playing)
        let supported = seekRange != nil
        let preparingHLSBuffer = syncEnabled
            && streams[index].format == "hls"
            && seekRange == nil
            && Date().timeIntervalSince(started) < 15
        let detail = !syncEnabled
            ? "Live playback · stream buffer managed automatically."
            : supported
                ? "Delay is measured from this stream’s available live edge."
                : preparingHLSBuffer
                    ? "Building an audio buffer for TV Sync. Delay controls will become available automatically."
                    : "Live playback. This stream does not provide a seekable delay buffer."
        publish(title: playing ? "Playing" : "Buffering…", detail: detail, buffering: !playing, supportsDelay: supported)
    }

    /// Counts advancing AVPlayer item time only while the player confirms it is
    /// rendering. The monotonic-clock cap rejects playlist discontinuities while
    /// still preserving delayed callbacks; explicit seeks and stream reloads
    /// clear the baseline before accounting resumes.
    private func recordAVPlayerInterval(position: TimeInterval, playing: Bool) {
        guard !usesPacketBuffer, !usesEnhancedPlayback, position.isFinite else {
            avPlayerAccountingSample = nil
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        defer { avPlayerAccountingSample = playing ? (position, uptime) : nil }
        guard playing, let previous = avPlayerAccountingSample else { return }
        let mediaDelta = position - previous.position
        let wallDelta = uptime - previous.uptime
        guard mediaDelta.isFinite, wallDelta.isFinite, mediaDelta > 0, wallDelta > 0 else { return }
        let rendered = min(mediaDelta, wallDelta)
        guard rendered > 0 else { return }
        onPlaybackInterval?(rendered, Date())
    }
    private func checkMetadataDiagnostics(at now: Date = Date()) {
        guard !syncEnabled, metadataOutput != nil, var timeline = metadataTimeline else { return }
        let context = [
            "source": "embedded", "stationID": stationID, "stationName": stationName,
            "streamID": selectedStreamID ?? "unknown"
        ]
        if timeline.successfulHeartbeatDue(at: now), timeline.lastSuccessfulContactAt != nil {
            var fields = timeline.elapsedFields(at: now)
            fields.merge(context) { _, new in new }
            fields["reason"] = "embedded-metadata-received"
            diagnose("metadata.providerHeartbeat", "Embedded metadata path is active", metadata: fields)
        }
        if let warning = timeline.silenceWarningDue(at: now) {
            var fields = timeline.elapsedFields(at: now)
            fields.merge(context) { _, new in new }
            fields["reason"] = "no-usable-song-metadata"
            fields["silenceWarningNumber"] = "\(warning.number)"
            fields["affectsDisplay"] = "\(!companionMetadataPreferred)"
            fields["preferredSource"] = companionMetadataPreferred ? "companion" : "embedded"
            let event = companionMetadataPreferred ? "metadata.sourceSilence" : "metadata.silence"
            let message = companionMetadataPreferred
                ? "Secondary embedded metadata has supplied no usable song"
                : "No usable song metadata has been accepted"
            diagnose(event, message, metadata: fields)
        }
        metadataTimeline = timeline
    }
    private func nextStream() {
        guard requested, retryAt == nil, !streams.isEmpty else { return }
        let attempt = recovery.nextAttempt(streamCount: streams.count, currentIndex: index)
        index = attempt.index
        retryAt = Date().addingTimeInterval(attempt.wait)
        generation = UUID(); seeking = false
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        hlsVocalBoostTap = nil
        lastProcessedFrames = 0; lastProcessedAt = .distantPast
        updateAudioEffectState()
        stopMetadataSidecar()
        packetEngine.stop(); packetEngine.suspendPreparation()
        enhancedEngine.stop()
        avPlayerAccountingSample = nil
        onTrackMetadata?(nil)
        diagnose("stream.retryScheduled", "Retrying station connection", metadata: [
            "cycle": "\(attempt.cycle)", "waitSeconds": "\(attempt.wait)",
            "streamID": streams[index].id
        ])
        publish(title: "Reconnecting…", detail: "Retry cycle \(attempt.cycle). Waiting for reception to return.", buffering: true, supportsDelay: false)
    }
    private func switchHLSIntoVocalBoostFallback() {
        hlsBoostFallbackAttempted = true
        usesEnhancedPlayback = true
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        hlsVocalBoostTap = nil
        avPlayerAccountingSample = nil
        started = Date(); lastAdvance = started
        setAudioEffectState(.preparing)
        diagnose("vocalBoost.hlsFallback", "Native tap did not process audio; trying unencrypted packed AAC", metadata: ["streamID": streams[index].id])
        enhancedEngine.configure(stream: streams[index], level: vocalBoost, deepBass: deepBass)
        enhancedEngine.start()
        if let url = StreamRequestPolicy.playbackURL(for: streams[index]) {
            startMetadataSidecar(url: url, stream: streams[index], token: generation)
        }
        publish(title: "Connecting…", detail: "Preparing HLS \(effectName)", buffering: true, supportsDelay: false)
    }

    private func switchHLSIntoPacketFallback() {
        guard requested, streams.indices.contains(index) else { return }
        hlsPacketFallbackAttempted = true
        generation = UUID(); seeking = false
        avPlayerAccountingSample = nil
        removeItemObservers()
        player.pause(); player.replaceCurrentItem(with: nil)
        hlsVocalBoostTap = nil
        lastProcessedFrames = 0; lastProcessedAt = .distantPast
        updateAudioEffectState()
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
                guard let self, let item, self.generation == token, self.player.currentItem === item, self.requested else { return }
                if item.status == .failed { self.nextStream() }
            }
        }
        itemObservers = [
            NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item, self.requested else { return }
                    self.diagnose("stream.playbackStalled", "AVPlayer reported a playback stall", metadata: ["streamID": self.selectedStreamID ?? "unknown"])
                    self.publish(title: "Buffering…", detail: "Waiting for enough stream data.", buffering: true, supportsDelay: self.seekRange != nil)
                    self.player.play()
                }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item, self.requested else { return }
                    self.nextStream()
                }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.generation == token, self.player.currentItem === item, self.requested else { return }
                    self.nextStream()
                }
            }
        ]
    }
    private func removeItemObservers() {
        player.cancelPendingPrerolls()
        metadataDelegate.cancelPendingMetadata()
        lastMetadataEvaluation = nil
        lastEmbeddedMetadata = nil
        embeddedMetadataReceiptNumber = 0
        metadataOutput?.setDelegate(nil, queue: nil)
        metadataOutput = nil
        metadataTimeline = nil
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
