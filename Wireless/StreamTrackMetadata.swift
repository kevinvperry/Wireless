import Foundation
import AVFoundation

enum StreamRequestPolicy {
    static func playbackURL(for stream: StationStream, sessionID: UUID = UUID()) -> URL? {
        guard let baseURL = stream.playableURL else { return nil }
        guard stream.format == "hls",
              baseURL.host?.lowercased().hasSuffix(".scastream.com.au") == true,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "wirelessSession" }
        queryItems.append(URLQueryItem(name: "wirelessSession", value: sessionID.uuidString.lowercased()))
        components.queryItems = queryItems
        return components.url ?? baseURL
    }
}

struct StreamTrackMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?

    var displayTitle: String { "\(title) · \(artist)" }
}

struct StreamTrackMetadataEvaluation: Equatable, Sendable {
    enum Outcome: String, Sendable {
        case accepted
        case noCurrentTrack = "empty.no-current-track"
        case noValues = "rejected.no-values"
        case malformedPayload = "rejected.malformed-payload"
        case missingTitle = "rejected.missing-title"
        case missingArtist = "rejected.missing-artist"
        case rejectedTitle = "rejected.title"
        case rejectedArtist = "rejected.artist"
    }

    let metadata: StreamTrackMetadata?
    let rawTitle: String?
    let rawArtist: String?
    let rawAlbum: String?
    let title: String?
    let artist: String?
    let album: String?
    let outcome: Outcome
    let classificationHints: [String]
    let providerDetails: [String: String]

    init(
        metadata: StreamTrackMetadata?,
        rawTitle: String? = nil,
        rawArtist: String? = nil,
        rawAlbum: String? = nil,
        title: String?,
        artist: String?,
        album: String?,
        outcome: Outcome,
        classificationHints: [String],
        providerDetails: [String: String] = [:]
    ) {
        self.metadata = metadata
        self.rawTitle = rawTitle ?? title
        self.rawArtist = rawArtist ?? artist
        self.rawAlbum = rawAlbum ?? album
        self.title = title
        self.artist = artist
        self.album = album
        self.outcome = outcome
        self.classificationHints = classificationHints
        self.providerDetails = providerDetails
    }

    var diagnosticFields: [String: String] {
        var fields = [
            "title": title ?? "<none>",
            "artist": artist ?? "<none>",
            "album": album ?? "<none>",
            "receivedTitleRaw": rawTitle ?? "<none>",
            "receivedArtistRaw": rawArtist ?? "<none>",
            "receivedAlbumRaw": rawAlbum ?? "<none>",
            "outcome": outcome.rawValue,
            "classificationHints": classificationHints.joined(separator: ",")
        ]
        fields.merge(providerDetails) { _, new in new }
        return fields
    }

    func addingProviderDetails(_ details: [String: String]) -> Self {
        var merged = providerDetails
        merged.merge(details) { _, new in new }
        return Self(
            metadata: metadata,
            rawTitle: rawTitle,
            rawArtist: rawArtist,
            rawAlbum: rawAlbum,
            title: title,
            artist: artist,
            album: album,
            outcome: outcome,
            classificationHints: classificationHints,
            providerDetails: merged
        )
    }

    /// Compares the broadcaster-supplied candidate and parser decision while
    /// deliberately ignoring changing transport and timing diagnostics.
    func hasSameCandidate(as other: Self?) -> Bool {
        guard let other else { return false }
        return rawTitle == other.rawTitle
            && rawArtist == other.rawArtist
            && rawAlbum == other.rawAlbum
            && title == other.title
            && artist == other.artist
            && album == other.album
            && outcome == other.outcome
            && classificationHints == other.classificationHints
    }
}

struct MetadataDiagnosticTimeline: Sendable {
    let startedAt: Date
    let heartbeatInterval: TimeInterval
    let silenceWarningInterval: TimeInterval
    private(set) var lastAcceptedSongAt: Date?
    private(set) var lastTrackChangeAt: Date?
    private(set) var lastSuccessfulContactAt: Date?
    private(set) var lastAcceptedMetadata: StreamTrackMetadata?
    private(set) var lastUsableMetadataReceiptAt: Date?
    private(set) var lastDistinctCandidateAt: Date?
    private(set) var acceptedReceiptCount = 0
    private(set) var identicalAcceptedReceiptCount = 0
    private var lastCandidateSignature: String?
    private var lastHeartbeatAt: Date
    private var lastSilenceWarningNumber = 0

    init(
        startedAt: Date = Date(),
        heartbeatInterval: TimeInterval = 60,
        silenceWarningInterval: TimeInterval = 120
    ) {
        self.startedAt = startedAt
        self.heartbeatInterval = max(1, heartbeatInterval)
        self.silenceWarningInterval = max(1, silenceWarningInterval)
        lastHeartbeatAt = startedAt
    }

    mutating func record(_ evaluation: StreamTrackMetadataEvaluation, at now: Date = Date()) -> [String: String] {
        lastSuccessfulContactAt = now
        let candidateSignature = [
            evaluation.rawTitle ?? "<none>",
            evaluation.rawArtist ?? "<none>",
            evaluation.rawAlbum ?? "<none>",
            evaluation.outcome.rawValue,
            evaluation.classificationHints.joined(separator: ",")
        ].joined(separator: "\u{1f}")
        if candidateSignature != lastCandidateSignature {
            lastDistinctCandidateAt = now
            lastCandidateSignature = candidateSignature
        }
        if let metadata = evaluation.metadata {
            lastUsableMetadataReceiptAt = now
            lastSilenceWarningNumber = 0
            if metadata != lastAcceptedMetadata {
                lastAcceptedMetadata = metadata
                lastAcceptedSongAt = now
                lastTrackChangeAt = now
                acceptedReceiptCount = 1
                identicalAcceptedReceiptCount = 0
            } else {
                acceptedReceiptCount += 1
                identicalAcceptedReceiptCount += 1
            }
        }
        return elapsedFields(at: now)
    }

    mutating func recordContact(at now: Date = Date()) -> [String: String] {
        lastSuccessfulContactAt = now
        return elapsedFields(at: now)
    }

    mutating func successfulHeartbeatDue(at now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(lastHeartbeatAt) >= heartbeatInterval else { return false }
        lastHeartbeatAt = now
        return true
    }

    mutating func silenceWarningDue(at now: Date = Date()) -> (number: Int, elapsed: TimeInterval)? {
        let elapsed = elapsedSinceUsableReceipt(at: now)
        let number = Int(elapsed / silenceWarningInterval)
        guard number > 0, number > lastSilenceWarningNumber else { return nil }
        lastSilenceWarningNumber = number
        return (number, elapsed)
    }

    func elapsedFields(at now: Date = Date()) -> [String: String] {
        var fields = [
            "lastAcceptedSongElapsedSeconds": String(format: "%.1f", elapsedSinceAcceptedSong(at: now)),
            "lastAcceptedSongState": lastAcceptedSongAt == nil ? "none-this-session" : "accepted",
            "lastDistinctCandidateElapsedSeconds": String(format: "%.1f", elapsedSinceDistinctCandidate(at: now)),
            "lastDistinctCandidateState": lastDistinctCandidateAt == nil ? "none-this-session" : "received",
            "lastTrackChangeElapsedSeconds": String(format: "%.1f", elapsedSinceTrackChange(at: now)),
            "lastTrackChangeState": lastTrackChangeAt == nil ? "none-this-session" : "changed",
            "lastUsableMetadataReceiptElapsedSeconds": String(format: "%.1f", elapsedSinceUsableReceipt(at: now)),
            "lastUsableMetadataReceiptState": lastUsableMetadataReceiptAt == nil ? "none-this-session" : "received",
            "acceptedReceiptCount": "\(acceptedReceiptCount)",
            "identicalAcceptedReceiptCount": "\(identicalAcceptedReceiptCount)"
        ]
        if let lastSuccessfulContactAt {
            fields["lastProviderContactElapsedSeconds"] = String(format: "%.1f", max(0, now.timeIntervalSince(lastSuccessfulContactAt)))
        } else {
            fields["lastProviderContactElapsedSeconds"] = "none-this-session"
        }
        return fields
    }

    private func elapsedSinceAcceptedSong(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastAcceptedSongAt ?? startedAt))
    }

    private func elapsedSinceTrackChange(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastTrackChangeAt ?? startedAt))
    }

    private func elapsedSinceDistinctCandidate(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastDistinctCandidateAt ?? startedAt))
    }

    private func elapsedSinceUsableReceipt(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastUsableMetadataReceiptAt ?? startedAt))
    }
}

struct MetadataFreshnessPolicy: Sendable {
    let timestampMaximumAge: TimeInterval
    let musicDisplayLifetime: TimeInterval
    let nonMusicDisplayLifetime: TimeInterval

    init(
        timestampMaximumAge: TimeInterval = 180,
        musicDisplayLifetime: TimeInterval = 600,
        nonMusicDisplayLifetime: TimeInterval = 120
    ) {
        self.timestampMaximumAge = max(1, timestampMaximumAge)
        self.musicDisplayLifetime = max(1, musicDisplayLifetime)
        self.nonMusicDisplayLifetime = max(1, nonMusicDisplayLifetime)
    }

    func displayLifetime(for evaluation: StreamTrackMetadataEvaluation) -> TimeInterval {
        evaluation.classificationHints == ["music-candidate"] ? musicDisplayLifetime : nonMusicDisplayLifetime
    }

    func embeddedTimestamp(in evaluation: StreamTrackMetadataEvaluation) -> Date? {
        for value in [evaluation.rawTitle, evaluation.rawArtist, evaluation.rawAlbum].compactMap({ $0 }) {
            guard let range = value.range(
                of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z"#,
                options: .regularExpression
            ) else { continue }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: String(value[range])) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: String(value[range])) { return date }
        }
        return nil
    }

    func diagnosticDetails(for evaluation: StreamTrackMetadataEvaluation, at now: Date = Date()) -> [String: String] {
        guard let timestamp = embeddedTimestamp(in: evaluation) else {
            return ["embeddedTimestampState": "absent", "candidateTimestampStale": "false"]
        }
        let age = now.timeIntervalSince(timestamp)
        return [
            "embeddedTimestamp": ISO8601DateFormatter().string(from: timestamp),
            "embeddedTimestampState": "present",
            "candidateTimestampAgeSeconds": String(format: "%.1f", age),
            "candidateTimestampMaximumAgeSeconds": String(format: "%.1f", timestampMaximumAge),
            "candidateTimestampStale": "\(age > timestampMaximumAge)"
        ]
    }
}

enum MetadataSourceArbitration {
    static func shouldApplyEmptyResult(source: String, companionEnabled: Bool, currentSource: String?) -> Bool {
        if source == "embedded", companionEnabled {
            return currentSource == "embedded"
        }
        return true
    }
}

enum StreamTrackMetadataParser {
    static func parse(_ items: [AVMetadataItem]) async -> StreamTrackMetadata? {
        await evaluate(items).metadata
    }

    static func evaluate(_ items: [AVMetadataItem]) async -> StreamTrackMetadataEvaluation {
        var title: String?
        var artist: String?
        var album: String?

        for item in items {
            guard let value = try? await item.load(.stringValue) else { continue }
            switch item.commonKey {
            case .commonKeyTitle: title = value
            case .commonKeyArtist: artist = value
            case .commonKeyAlbumName: album = value
            default:
                if item.identifier == .icyMetadataStreamTitle { title = value }
            }
        }

        return evaluate(title: title, artist: artist, album: album)
    }

    static func validated(title: String?, artist: String?, album: String? = nil) -> StreamTrackMetadata? {
        evaluate(title: title, artist: artist, album: album).metadata
    }

    static func evaluate(title: String?, artist: String?, album: String? = nil) -> StreamTrackMetadataEvaluation {
        let rawTitle = title
        let rawArtist = artist
        let rawAlbum = album
        var title = clean(title)
        var artist = clean(artist)
        let album = clean(album)
        let hints = classificationHints(title: title, artist: artist, album: album)
        let values = [title, artist, album].compactMap { $0 }
        guard !values.isEmpty else {
            return StreamTrackMetadataEvaluation(metadata: nil, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: nil, artist: nil, album: nil, outcome: .noValues, classificationHints: hints)
        }
        if artist == nil, let combined = title, let split = splitCombinedTitle(combined) {
            artist = split.artist
            title = split.title
        }
        guard title != nil else {
            return StreamTrackMetadataEvaluation(metadata: nil, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: nil, artist: artist, album: album, outcome: .missingTitle, classificationHints: hints)
        }
        guard artist != nil else {
            return StreamTrackMetadataEvaluation(metadata: nil, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: title, artist: nil, album: album, outcome: .missingArtist, classificationHints: hints)
        }
        guard let acceptedTitle = acceptable(title) else {
            return StreamTrackMetadataEvaluation(metadata: nil, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: title, artist: artist, album: album, outcome: .rejectedTitle, classificationHints: hints)
        }
        guard let acceptedArtist = acceptable(artist) else {
            return StreamTrackMetadataEvaluation(metadata: nil, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: title, artist: artist, album: album, outcome: .rejectedArtist, classificationHints: hints)
        }
        let metadata = StreamTrackMetadata(title: acceptedTitle, artist: acceptedArtist, album: acceptable(album))
        return StreamTrackMetadataEvaluation(metadata: metadata, rawTitle: rawTitle, rawArtist: rawArtist, rawAlbum: rawAlbum, title: title, artist: artist, album: album, outcome: .accepted, classificationHints: hints)
    }

    static func malformedPayloadEvaluation() -> StreamTrackMetadataEvaluation {
        StreamTrackMetadataEvaluation(
            metadata: nil,
            title: nil,
            artist: nil,
            album: nil,
            outcome: .malformedPayload,
            classificationHints: ["technical-marker"]
        )
    }

    static func noCurrentTrackEvaluation() -> StreamTrackMetadataEvaluation {
        StreamTrackMetadataEvaluation(
            metadata: nil,
            title: nil,
            artist: nil,
            album: nil,
            outcome: .noCurrentTrack,
            classificationHints: ["no-current-track"]
        )
    }

    private static func classificationHints(title: String?, artist: String?, album: String?) -> [String] {
        let values = [title, artist, album].compactMap { $0 }
        let combined = values.joined(separator: " ").lowercased()
        var hints: [String] = []
        if values.contains(where: { isAssetPlayoutLabel($0) || isStandaloneTimestamp($0) })
            || combined.range(of: #"https?://|^[\W_]+$|\d{4}-\d{2}-\d{2}t\d{2}:\d{2}"#, options: .regularExpression) != nil {
            hints.append("technical-marker")
        }
        if combined.range(of: #"\b(advertisement|commercial|ad break|advert break|sponsored by)\b"#, options: .regularExpression) != nil {
            hints.append("advertisement")
        }
        if combined.range(of: #"\b(breakfast|drive|mornings|afternoons|nights|show|minimix|station id)\b"#, options: .regularExpression) != nil
            || artist?.caseInsensitiveCompare("Various Artists") == .orderedSame {
            hints.append("programme-label")
        }
        if hints.isEmpty { hints.append("music-candidate") }
        return hints
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

    private static func isAssetPlayoutLabel(_ value: String) -> Bool {
        guard let value = clean(value) else { return false }
        // Classification only. Asset labels are deliberately not rejected while
        // SCA's embedded metadata path is being verified.
        return value.range(of: #"(?i)^asset[\s_-]+[a-z]+\b"#, options: .regularExpression) != nil
    }

    private static func isStandaloneTimestamp(_ value: String) -> Bool {
        guard let value = clean(value) else { return false }
        return value.range(of: #"(?i)^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$"#, options: .regularExpression) != nil
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
        let breakLabels = ["ad break", "advert break"]
        guard !isStandaloneTimestamp(value), !breakLabels.contains(lower),
              !rejectedPhrases.contains(where: lower.contains),
              !lower.hasPrefix("http://"), !lower.hasPrefix("https://"),
              lower.range(of: #"^[\W_]+$"#, options: .regularExpression) == nil else { return nil }
        return value
    }
}
