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
    private let receive: @Sendable (Event) -> Void

    init(receive: @escaping @Sendable (Event) -> Void) { self.receive = receive }

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
                completed = true; receive(.failed("The stream’s audio format changed. Try again.")); return
            }
            format = buffer.format
            do {
                try generator.append(buffer, at: nil)
                seconds += Double(buffer.frameLength) / buffer.format.sampleRate
                if seconds >= 10 {
                    let session = SHSession()
                    let signature = generator.signature()
                    guard signature.duration >= session.catalog.minimumQuerySignatureDuration,
                          signature.duration <= session.catalog.maximumQuerySignatureDuration else {
                        completed = true; receive(.failed("This audio sample could not be recognised. Try again.")); return
                    }
                    self.session = session; session.delegate = self
                    receive(.matching)
                    session.match(signature)
                }
            } catch {
                completed = true; receive(.failed("This stream’s audio format cannot be used for song identification."))
            }
        }
    }

    func cancel() { queue.async { [self] in completed = true; session?.delegate = nil; session = nil } }

    func session(_ session: SHSession, didFind match: SHMatch) {
        let song = match.mediaItems.compactMap(RecognisedSong.init).max { $0.confidence < $1.confidence }
        let sessionID = ObjectIdentifier(session)
        queue.async { [self] in
            guard !completed, self.session.map(ObjectIdentifier.init) == sessionID else { return }
            completed = true
            if let song { receive(.found(song)) } else { receive(.noMatch) }
        }
    }
    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        let failed = error != nil
        let errorDomain = (error as NSError?)?.domain ?? "none"
        let errorCode = (error as NSError?)?.code ?? 0
        let sessionID = ObjectIdentifier(session)
        queue.async { [self] in
            guard !completed, self.session.map(ObjectIdentifier.init) == sessionID else { return }
            completed = true
            if failed {
                StreamDiagnosticLogger.shared.record("recognition.failed", "Shazam request failed", metadata: [
                    "errorDomain": errorDomain, "errorCode": String(errorCode)
                ])
            }
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
    init(timeout: Duration = .seconds(30)) { self.timeout = timeout }
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

    func start(explanation: String) -> SongRecognitionWorker {
        cancel()
        let id = attempt.begin()
        sourceExplanation = explanation
        state = .listening; saveMessage = nil; saved = false; saving = false
        let worker = SongRecognitionWorker { [weak self] event in
            Task { @MainActor in
                guard let self, self.attempt.accepts(id), self.state.isWorking else { return }
                switch event {
                case .matching: self.state = .matching; self.stopAudio?()
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
            self.finish(.failed(self.state == .listening
                ? "Wireless could not obtain enough audio from this stream. Try another stream in Audio Controls."
                : "Shazam took too long to respond. Check your connection and try again."))
        }
        return worker
    }

    func unavailable(_ message: String) { cancel(); sourceExplanation = ""; state = .failed(message) }
    func cancel() {
        attempt.cancel(); deadline?.cancel(); deadline = nil
        worker?.cancel(); worker = nil; stopAudio?()
        state = .ready; saving = false; saved = false; saveMessage = nil; sourceExplanation = ""
    }
    private func finish(_ result: SongRecognitionState) {
        state = result; deadline?.cancel(); deadline = nil
        worker?.cancel(); worker = nil; stopAudio?()
    }
    func saveToShazam() async {
        #if DEBUG
        if previewOnly { saveMessage = "Preview only — no song was saved."; return }
        #endif
        guard case .found(let song) = state, let shazamID = song.shazamID,
              !saving, !saved else { return }
        let id = attempt.id
        saving = true; saveMessage = nil
        do {
            let item = SHMediaItem(properties: [.shazamID: shazamID])
            try await SHLibrary.default.addItems([item])
            guard attempt.accepts(id) else { return }
            saved = true; saving = false; saveMessage = "Saved to your Shazam library."
        } catch {
            guard attempt.accepts(id) else { return }
            saving = false; saveMessage = "Could not save to Shazam. Please try again."
        }
    }
}
