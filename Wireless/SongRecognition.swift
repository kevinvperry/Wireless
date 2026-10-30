import AVFoundation
import Combine
import ShazamKit
import Synchronization

struct RecognisedSong: Codable, Equatable, Sendable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let appleMusicURL: URL?
    let shazamURL: URL?
    let shazamID: String?
    let confidence: Float

    init(title: String, artist: String, artworkURL: URL? = nil, appleMusicURL: URL? = nil,
         shazamURL: URL? = nil, shazamID: String? = nil, confidence: Float = 0) {
        self.title = title; self.artist = artist; self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL; self.shazamURL = shazamURL
        self.shazamID = shazamID; self.confidence = confidence
    }

    init?(_ item: SHMatchedMediaItem) {
        guard let title = item.title, !title.isEmpty,
              let artist = item.artist, !artist.isEmpty else { return nil }
        self.title = title; self.artist = artist
        artworkURL = item.artworkURL; appleMusicURL = item.appleMusicURL
        shazamURL = item.webURL; shazamID = item.shazamID; confidence = item.confidence
    }
}

/// A new identity for every attempt prevents late recognition callbacks
/// from changing a newer attempt, a different station or a dismissed sheet.
struct SongRecognitionAttempt: Equatable, Sendable {
    private(set) var id = UUID()
    private(set) var active = false
    mutating func begin() -> UUID { id = UUID(); active = true; return id }
    mutating func cancel() { id = UUID(); active = false }
    func accepts(_ candidate: UUID) -> Bool { active && id == candidate }
}

enum SongRecognitionState: Equatable {
    case ready, listening, matching, found(RecognisedSong), noMatch, failed(String)
    var isWorking: Bool { self == .listening || self == .matching }
    var diagnosticName: String {
        switch self {
        case .ready: "ready"
        case .listening: "capturing"
        case .matching: "matching"
        case .found: "found"
        case .noMatch: "no-match"
        case .failed: "failed"
        }
    }
}

/// Owns all Shazam signature/session work on one serial queue, away from audio
/// rendering and the main actor. Input buffers are exclusively owned snapshots.
final class SongRecognitionWorker: NSObject, SHSessionDelegate, @unchecked Sendable {
    enum Event: Sendable { case matching, found(RecognisedSong), noMatch, failed(String) }
    private let queue = DispatchQueue(label: "au.com.kevmarl.Wireless.songRecognition")
    typealias Submission = @Sendable (SHSession, AVAudioPCMBuffer, AVAudioTime) -> Void
    private let submitBuffer: Submission
    private var receivedNoMatch = false
    private var announcedMatching = false
    private let inputFrames = Atomic<Int>(0)
    var captureFrameCount: Int { inputFrames.load(ordering: .relaxed) }
    func resetCaptureForFallback() {
        queue.async { [self] in
            guard !completed else { return }
            diagnostics.record("capture.reset", "Discarding partial fingerprint before switching audio source", ["discardedSeconds": String(seconds)])
            session?.delegate = nil; session = nil
            receivedNoMatch = false; announcedMatching = false
            format = nil; seconds = 0
            buffers = 0; frames = 0; nextProgress = 0
        }
    }
    private var session: SHSession?
    private var seconds: Double = 0
    private var format: AVAudioFormat?
    private var completed = false
    let diagnostics: ShazamDiagnosticContext
    private var buffers = 0
    private var frames: UInt64 = 0
    private var nextProgress = 0.0
    private let receive: @Sendable (Event) -> Void

    init(diagnostics: ShazamDiagnosticContext = ShazamDiagnosticContext(),
         submitBuffer: @escaping Submission = { $0.matchStreamingBuffer($1, at: $2) },
         receive: @escaping @Sendable (Event) -> Void) {
        self.diagnostics = diagnostics; self.receive = receive; self.submitBuffer = submitBuffer
    }

    // The producer transfers an independently allocated buffer and never reuses
    // its storage. Only this queue reads it after delivery.
    private struct OwnedPCM: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
    func append(_ buffer: AVAudioPCMBuffer) {
        inputFrames.wrappingAdd(Int(buffer.frameLength), ordering: .relaxed)
        let owned = OwnedPCM(buffer: buffer)
        queue.async { [self] in
            let buffer = owned.buffer
            guard !completed, buffer.frameLength > 0 else { return }
            // Discontinuities/formats must never be concatenated into one signature.
            if let format, format != buffer.format {
                diagnostics.record("audio.formatChanged", "PCM format changed during capture",
                    ShazamDiagnosticContext.audioFormat(buffer.format).merging(["capturedSeconds": String(seconds)]) { _, new in new })
                completed = true; receive(.failed("The stream’s audio format changed. Try again.")); return
            }
            if format == nil {
                diagnostics.record("audio.firstBuffer", "First PCM buffer delivered to fingerprint generator",
                    ShazamDiagnosticContext.audioFormat(buffer.format).merging(["frameLength": String(buffer.frameLength)]) { _, new in new })
            }
            format = buffer.format
            let time = AVAudioTime(sampleTime: AVAudioFramePosition(frames), atRate: buffer.format.sampleRate)
            buffers += 1; frames += UInt64(buffer.frameLength)
            do {
                seconds += Double(buffer.frameLength) / buffer.format.sampleRate
                if diagnostics.enabled, seconds >= nextProgress {
                    nextProgress = seconds + 2
                    var details = ["buffers": String(buffers), "frames": String(frames), "capturedSeconds": String(seconds)]
                    if let channels = buffer.floatChannelData, buffer.format.commonFormat == .pcmFormatFloat32 {
                        let count = Int(buffer.frameLength)
                        let channelCount = Int(buffer.format.channelCount)
                        var peak: Float = 0; var sum: Double = 0; var invalid = 0
                        for channel in 0..<channelCount {
                            for frame in 0..<count {
                                let value = buffer.format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                                if value.isFinite { peak = max(peak, abs(value)); sum += Double(value) * Double(value) }
                                else { invalid += 1 }
                            }
                        }
                        details["windowPeak"] = String(peak)
                        details["windowRMS"] = String(sqrt(sum / Double(max(1, count * channelCount))))
                        details["windowNonFiniteSamples"] = String(invalid)
                    } else { details["signalStatistics"] = "unavailable-for-this-PCM-type" }
                    diagnostics.record("audio.progress", "PCM capture progress (signal statistics only)", details)
                }
                let active: SHSession
                if let session { active = session }
                else {
                    active = SHSession(); session = active; active.delegate = self
                    diagnostics.record("stream.started", "Feeding PCM to ShazamKit streaming matcher", [
                        "catalogueMinimumDuration": String(active.catalog.minimumQuerySignatureDuration),
                        "catalogueMaximumDuration": String(active.catalog.maximumQuerySignatureDuration),
                        "matchingMode": "streaming", "captureGeneration": "new-session"])
                }
                submitBuffer(active, buffer, time)
                if !announcedMatching, seconds >= active.catalog.minimumQuerySignatureDuration {
                    announcedMatching = true
                    diagnostics.record("stream.matching", "Minimum query duration reached; streaming matcher remains active", ["capturedSeconds": String(seconds)])
                    receive(.matching)
                }
            }
        }
    }

    func deadlineReached() {
        queue.async { [self] in
            guard !completed else { return }
            completed = true
            diagnostics.record("stream.deadline", "Streaming recognition reached overall deadline", ["capturedSeconds": String(seconds), "receivedNoMatch": String(receivedNoMatch)])
            if receivedNoMatch { receive(.noMatch) }
            else { receive(.failed(seconds == 0
                ? "Wireless could not obtain enough audio from this stream. Try another stream in Audio Controls."
                : "Shazam took too long to respond. Check your connection and try again.")) }
        }
    }

    func cancel(reason: String = "cancelled") {
        queue.async { [self] in
            diagnostics.record("audio.summary", "Capture worker stopped", ["reason": reason, "buffers": String(buffers),
                "frames": String(frames), "capturedSeconds": String(seconds), "streamingSessionStarted": String(session != nil), "matchingMode": "streaming",
                "workerCompleted": String(completed)])
            completed = true; session?.delegate = nil; session = nil
        }
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        let song = match.mediaItems.compactMap(RecognisedSong.init).max { $0.confidence < $1.confidence }
        let sessionID = ObjectIdentifier(session)
        let candidateCount = match.mediaItems.count
        let signatureDuration = match.querySignature.duration
        queue.async { [self] in
            guard !completed, self.session.map(ObjectIdentifier.init) == sessionID else {
                diagnostics.record("callback.ignored", "Late or unrelated match callback ignored"); return
            }
            diagnostics.record("callback.match", "Shazam returned catalogue candidates", ["signatureDuration": String(signatureDuration), "capturedSeconds": String(seconds), "candidateCount": String(candidateCount),
                "usableCandidate": String(song != nil), "confidence": song.map { String($0.confidence) } ?? "none",
                "shazamID": song?.shazamID ?? "none", "title": song?.title ?? "none", "artist": song?.artist ?? "none",
                "hasArtwork": String(song?.artworkURL != nil), "hasAppleMusicLink": String(song?.appleMusicURL != nil), "hasShazamLink": String(song?.shazamURL != nil)])
            if let song { completed = true; receive(.found(song)) }
            else { receivedNoMatch = true }
        }
    }
    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        let failed = error != nil
        let errorDetails = error.map(ShazamDiagnosticContext.errorFields) ?? [:]
        let duration = signature.duration
        let sessionID = ObjectIdentifier(session)
        queue.async { [self] in
            guard !completed, self.session.map(ObjectIdentifier.init) == sessionID else {
                diagnostics.record("callback.ignored", "Late or unrelated no-match/error callback ignored"); return
            }
            if failed { completed = true } else { receivedNoMatch = true }
            diagnostics.record(failed ? "request.failed" : "callback.noMatch",
                failed ? "Shazam catalogue request failed" : "Shazam returned no matching recording",
                errorDetails.merging(["signatureDuration": String(duration), "capturedSeconds": String(seconds), "callbackHasError": String(failed), "continuingStreaming": String(!failed)]) { _, new in new })
            if failed { receive(.failed("Shazam could not complete the request. Check your internet connection and try again.")) }
            // A streaming session can return an early no-match and then succeed
            // with more audio. Continue until a usable result or the deadline.
        }
    }
}

@MainActor final class SongRecognition: ObservableObject {
    @Published private(set) var state: SongRecognitionState = .ready
    @Published private(set) var sourceExplanation = ""
    private let timeout: Duration
    private let submitBuffer: SongRecognitionWorker.Submission
    private let diagnosticSink: ShazamDiagnosticContext.Sink?
    private var diagnostics: ShazamDiagnosticContext?
    init(timeout: Duration = .seconds(30), diagnosticSink: ShazamDiagnosticContext.Sink? = nil,
         submitBuffer: @escaping SongRecognitionWorker.Submission = { $0.matchStreamingBuffer($1, at: $2) }) {
        self.timeout = timeout; self.diagnosticSink = diagnosticSink; self.submitBuffer = submitBuffer
    }
    #if DEBUG
    convenience init(previewState: SongRecognitionState) {
        self.init(); state = previewState; _ = attempt.begin()
    }
    #endif
    private var attempt = SongRecognitionAttempt()
    private var worker: SongRecognitionWorker?
    private var deadline: Task<Void, Never>?
    var stopAudio: (() -> Void)?
    var onRecognised: ((RecognisedSong, UUID) -> Bool)?

    func start(explanation: String, diagnosticFields: [String: String] = [:], privateNames: [String] = []) -> SongRecognitionWorker {
        cancel(reason: "replaced-by-new-attempt")
        let id = attempt.begin()
        let trace = ShazamDiagnosticContext(id: id,
            fields: ShazamDiagnosticContext.environment().merging(diagnosticFields) { _, new in new }, sink: diagnosticSink, privateNames: privateNames)
        diagnostics = trace
        trace.record("attempt.started", "Identify song requested", ["timeout": String(describing: timeout), "matchingMode": "streaming"])

        sourceExplanation = explanation
        state = .listening
        let worker = SongRecognitionWorker(diagnostics: trace, submitBuffer: submitBuffer) { [weak self] event in
            Task { @MainActor in
                guard let self, self.attempt.accepts(id), self.state.isWorking else {
                    trace.record("result.ignored", "Result rejected because the attempt is no longer current"); return
                }
                switch event {
                case .matching:
                    trace.record("attempt.matching", "Streaming recognition is matching while audio capture continues")
                    self.state = .matching
                case .found(let song): self.finish(.found(song))
                case .noMatch: self.finish(.noMatch)
                case .failed(let message): self.finish(.failed(message))
                }
            }
        }
        self.worker = worker
        let timeout = timeout
        deadline = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.attempt.accepts(id) else { return }
            trace.record("attempt.timeout", "Identify song deadline reached", ["phase": self.state == .listening ? "capture" : "catalogue-request"])
            self.worker?.deadlineReached()
        }
        return worker
    }

    func updateSourceExplanation(_ explanation: String) {
        guard state.isWorking else { return }; sourceExplanation = explanation
    }

    func recordEnvironmentChange(_ event: String, _ fields: [String: String]) {
        guard state.isWorking else { return }
        diagnostics?.record(event, "Environment changed during identification", fields)
    }

    func reject(_ message: String, fields: [String: String]) {
        cancel(reason: "replaced-by-rejected-request")
        diagnostics = ShazamDiagnosticContext(fields: ShazamDiagnosticContext.environment().merging(fields) { _, new in new }, sink: diagnosticSink)
        diagnostics?.record("attempt.rejected", "Identify song request rejected before capture", ["reason": message])
        state = .failed(message)
    }
    func unavailable(_ message: String) {
        diagnostics?.record("attempt.unavailable", "Identification unavailable", ["reason": message])
        cancel(reason: "unavailable: " + message); sourceExplanation = ""; state = .failed(message)
    }
    func cancel(reason: String = "user-cancelled") {
        if attempt.active { diagnostics?.record("attempt.cancelled", "Identification cancelled or dismissed", ["reason": reason, "state": state.diagnosticName]) }
        attempt.cancel(); deadline?.cancel(); deadline = nil
        worker?.cancel(reason: reason); worker = nil; stopAudio?()
        state = .ready; sourceExplanation = ""
    }
    private func finish(_ result: SongRecognitionState) {
        if case .found(let song) = result, let onRecognised {
            let saved = onRecognised(song, attempt.id)
            diagnostics?.record(saved ? "history.saved" : "history.failed", "Local recognition history update", ["saved": String(saved)])
        }
        diagnostics?.record("attempt.finished", "Identification reached a terminal result", ["outcome": result.diagnosticName])
        state = result; deadline?.cancel(); deadline = nil
        worker?.cancel(reason: "terminal-" + result.diagnosticName); worker = nil; stopAudio?()
    }
}
