import AVFoundation
import Combine
import ShazamKit

struct RecognisedSong: Equatable, Sendable {
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

/// A new identity for every attempt prevents late recognition/library callbacks
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
    private var generator = SHSignatureGenerator()
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
         receive: @escaping @Sendable (Event) -> Void) {
        self.diagnostics = diagnostics; self.receive = receive
    }

    // The producer transfers an independently allocated buffer and never reuses
    // its storage. Only this queue reads it after delivery.
    private struct OwnedPCM: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
    func append(_ buffer: AVAudioPCMBuffer) {
        let owned = OwnedPCM(buffer: buffer)
        queue.async { [self] in
            let buffer = owned.buffer
            guard !completed, session == nil, buffer.frameLength > 0 else { return }
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
            buffers += 1; frames += UInt64(buffer.frameLength)
            do {
                try generator.append(buffer, at: nil)
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
                if seconds >= 10 {
                    let session = SHSession()
                    let signature = generator.signature()
                    diagnostics.record("signature.generated", "Generated Shazam fingerprint", [
                        "signatureDuration": String(signature.duration),
                        "signatureByteCount": diagnostics.enabled ? String(signature.dataRepresentation.count) : "not-inspected",
                        "catalogueMinimumDuration": String(session.catalog.minimumQuerySignatureDuration),
                        "catalogueMaximumDuration": String(session.catalog.maximumQuerySignatureDuration),
                        "buffers": String(buffers), "frames": String(frames)
                    ])
                    guard signature.duration >= session.catalog.minimumQuerySignatureDuration,
                          signature.duration <= session.catalog.maximumQuerySignatureDuration else {
                        diagnostics.record("signature.rejected", "Fingerprint duration outside catalogue limits")
                        completed = true; receive(.failed("This audio sample could not be recognised. Try again.")); return
                    }
                    self.session = session; session.delegate = self
                    receive(.matching)
                    diagnostics.record("request.submitted", "Submitting fingerprint to Shazam catalogue")
                    session.match(signature)
                    diagnostics.record("request.invoked", "SHSession.match returned; awaiting delegate callback")
                }
            } catch {
                diagnostics.error("signature.failed", "Fingerprint generator rejected PCM audio", error, details: ["capturedSeconds": String(seconds)])
                completed = true; receive(.failed("This stream’s audio format cannot be used for song identification."))
            }
        }
    }

    func cancel(reason: String = "cancelled") {
        queue.async { [self] in
            diagnostics.record("audio.summary", "Capture worker stopped", ["reason": reason, "buffers": String(buffers),
                "frames": String(frames), "capturedSeconds": String(seconds), "requestSubmitted": String(session != nil),
                "workerCompleted": String(completed)])
            completed = true; session?.delegate = nil; session = nil
        }
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        let song = match.mediaItems.compactMap(RecognisedSong.init).max { $0.confidence < $1.confidence }
        let sessionID = ObjectIdentifier(session)
        let candidateCount = match.mediaItems.count
        queue.async { [self] in
            guard !completed, self.session.map(ObjectIdentifier.init) == sessionID else {
                diagnostics.record("callback.ignored", "Late or unrelated match callback ignored"); return
            }
            diagnostics.record("callback.match", "Shazam returned catalogue candidates", ["candidateCount": String(candidateCount),
                "usableCandidate": String(song != nil), "confidence": song.map { String($0.confidence) } ?? "none",
                "shazamID": song?.shazamID ?? "none", "title": song?.title ?? "none", "artist": song?.artist ?? "none",
                "hasArtwork": String(song?.artworkURL != nil), "hasAppleMusicLink": String(song?.appleMusicURL != nil)])
            completed = true
            if let song { receive(.found(song)) } else { receive(.noMatch) }
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
            completed = true
            diagnostics.record(failed ? "request.failed" : "callback.noMatch",
                failed ? "Shazam catalogue request failed" : "Shazam returned no matching recording",
                errorDetails.merging(["signatureDuration": String(duration), "callbackHasError": String(failed)]) { _, new in new })
            receive(failed ? .failed("Shazam could not complete the request. Check your internet connection and try again.") : .noMatch)
        }
    }
}

@MainActor final class SongRecognition: ObservableObject {
    @Published private(set) var state: SongRecognitionState = .ready
    @Published private(set) var saveMessage: String?
    @Published private(set) var saving = false
    @Published private(set) var saved = false
    @Published private(set) var sourceExplanation = ""
    private let timeout: Duration
    private let diagnosticSink: ShazamDiagnosticContext.Sink?
    private var diagnostics: ShazamDiagnosticContext?
    init(timeout: Duration = .seconds(30), diagnosticSink: ShazamDiagnosticContext.Sink? = nil) {
        self.timeout = timeout; self.diagnosticSink = diagnosticSink
    }
    #if DEBUG
    private var previewOnly = false
    convenience init(previewState: SongRecognitionState) {
        self.init(); previewOnly = true; state = previewState; _ = attempt.begin()
    }
    #endif
    private var attempt = SongRecognitionAttempt()
    private var worker: SongRecognitionWorker?
    private var deadline: Task<Void, Never>?
    var stopAudio: (() -> Void)?

    func start(explanation: String, diagnosticFields: [String: String] = [:], privateNames: [String] = []) -> SongRecognitionWorker {
        cancel(reason: "replaced-by-new-attempt")
        let id = attempt.begin()
        let trace = ShazamDiagnosticContext(id: id,
            fields: ShazamDiagnosticContext.environment().merging(diagnosticFields) { _, new in new }, sink: diagnosticSink, privateNames: privateNames)
        diagnostics = trace
        trace.record("attempt.started", "Identify song requested", ["timeout": String(describing: timeout), "captureTargetSeconds": "10"])

        sourceExplanation = explanation
        state = .listening; saveMessage = nil; saved = false; saving = false
        let worker = SongRecognitionWorker(diagnostics: trace) { [weak self] event in
            Task { @MainActor in
                guard let self, self.attempt.accepts(id), self.state.isWorking else {
                    trace.record("result.ignored", "Result rejected because the attempt is no longer current"); return
                }
                switch event {
                case .matching:
                    trace.record("attempt.matching", "Audio capture complete; waiting for Shazam")
                    self.state = .matching; self.stopAudio?()
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
            self.finish(.failed(self.state == .listening
                ? "Wireless could not obtain enough audio from this stream. Try another stream in Audio Controls."
                : "Shazam took too long to respond. Check your connection and try again."))
        }
        return worker
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
        state = .ready; saving = false; saved = false; saveMessage = nil; sourceExplanation = ""
    }
    private func finish(_ result: SongRecognitionState) {
        diagnostics?.record("attempt.finished", "Identification reached a terminal result", ["outcome": result.diagnosticName])
        state = result; deadline?.cancel(); deadline = nil
        worker?.cancel(reason: "terminal-" + result.diagnosticName); worker = nil; stopAudio?()
    }
    func saveToShazam() async {
        #if DEBUG
        if previewOnly { saveMessage = "Preview only — no song was saved."; return }
        #endif
        guard case .found(let song) = state, let shazamID = song.shazamID,
              !saving, !saved else { return }
        let id = attempt.id
        saving = true; saveMessage = nil
        let trace = diagnostics
        trace?.record("library.saveStarted", "Saving matched recording to Shazam library", ["shazamID": shazamID])
        do {
            let item = SHMediaItem(properties: [.shazamID: shazamID])
            try await SHLibrary.default.addItems([item])
            trace?.record("library.saved", "Shazam library save succeeded", ["attemptStillCurrent": String(attempt.accepts(id))])
            guard attempt.accepts(id) else { return }
            saved = true; saving = false; saveMessage = "Saved to your Shazam library."
        } catch {
            trace?.error("library.saveFailed", "Shazam library save failed", error)
            guard attempt.accepts(id) else { return }
            saving = false; saveMessage = "Could not save to Shazam. Please try again."
        }
    }
}
