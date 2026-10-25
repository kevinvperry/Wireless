import Foundation

enum CompanionMetadataSource: Equatable, Sendable {
    case triton(mountName: String)
    case abc(serviceID: String)
    case listnr(streamKey: String)

    static func source(for station: DirectoryStation, selectedStreamID: String? = nil) -> Self? {
        if station.network.caseInsensitiveCompare("ABC") == .orderedSame {
            let rawStationName = station.name.lowercased()
            let stationName = rawStationName.filter(\.isLetter)
            if rawStationName.contains("classic 2") { return .abc(serviceID: "CLASSIC2") }
            if stationName.contains("hottest") { return .abc(serviceID: "H100") }
            if stationName.contains("unearthed") { return .abc(serviceID: "UNEARTHED") }
            let serviceName = (station.subnetwork ?? station.name)
                .lowercased()
                .filter(\.isLetter)
            if serviceName == "doublej" { return .abc(serviceID: "DOUBLEJ") }
            if serviceName == "triplej" { return .abc(serviceID: "TRIPLEJ") }
            if serviceName == "abcclassic" { return .abc(serviceID: "CLASSIC") }
            if serviceName == "abccountry" { return .abc(serviceID: "COUNTRY") }
            if serviceName == "abcjazz" { return .abc(serviceID: "JAZZ") }
            if serviceName == "abckidslisten" { return .abc(serviceID: "KIDSLISTEN") }
        }

        let selected = station.playableStreams.first { $0.id == selectedStreamID }
        let candidates = [selected, station.preferredStream].compactMap { $0 }
            + station.playableStreams
        // SCA's broadcast services carry timely metadata in their audio streams.
        // Do not let the LiSTNR companion channel override Metro or Regional
        // Triple M and Hit metadata merely because the stream is SCA-hosted.
        if station.isMusicFocused, !station.prefersEmbeddedSCABroadcastMetadata {
            if let streamKey = candidates.lazy.compactMap(\.listnrStreamKey).first {
                return .listnr(streamKey: streamKey)
            }
        }
        guard let mountName = candidates.lazy.compactMap(\.tritonMountName).first else { return nil }
        return .triton(mountName: mountName)
    }

    static func unavailableReason(for station: DirectoryStation, selectedStreamID: String? = nil) -> String {
        let selected = station.playableStreams.first { $0.id == selectedStreamID }
        let candidates = [selected, station.preferredStream].compactMap { $0 } + station.playableStreams
        if station.prefersEmbeddedSCABroadcastMetadata,
           candidates.contains(where: { $0.listnrStreamKey != nil }) {
            return "sca-broadcast-uses-embedded-metadata"
        }
        if candidates.contains(where: { $0.listnrStreamKey != nil }), !station.isMusicFocused {
            return "listnr-station-not-music-focused"
        }
        if station.network.caseInsensitiveCompare("ABC") == .orderedSame {
            return station.abcProgrammeServiceID == nil
                ? "abc-service-has-no-supported-music-endpoint"
                : "abc-programme-guide-used-instead-of-song-provider"
        }
        return "no-supported-official-provider"
    }

    var url: URL {
        switch self {
        case .triton(let mountName):
            var components = URLComponents(string: "https://np.tritondigital.com/public/nowplaying")!
            components.queryItems = [
                URLQueryItem(name: "mountName", value: mountName),
                URLQueryItem(name: "numberToFetch", value: "1"),
                URLQueryItem(name: "eventType", value: "track")
            ]
            return components.url!
        case .abc(let serviceID):
            return URL(string: "https://www.abc.net.au/core-next/api/musicNowPlaying/\(serviceID)")!
        case .listnr:
            return URL(string: "https://api.listnr.com/v2")!
        }
    }

    func parse(_ data: Data) -> StreamTrackMetadata? {
        evaluate(data).metadata
    }

    func evaluate(_ data: Data) -> StreamTrackMetadataEvaluation {
        switch self {
        case .triton: TritonNowPlayingParser.evaluate(data)
        case .abc: ABCNowPlayingParser.evaluate(data)
        case .listnr: LiSTNRNowPlayingParser.evaluate(data)
        }
    }

    var diagnosticName: String {
        switch self {
        case .triton(let mountName): "triton:\(mountName)"
        case .abc(let serviceID): "abc:\(serviceID)"
        case .listnr(let streamKey): "listnr:\(streamKey)"
        }
    }
}

enum LiSTNRDirectoryParser {
    private struct Response: Decodable { let data: Payload? }
    private struct Payload: Decodable { let stations: [Station] }
    private struct Station: Decodable { let audioStreams: [AudioStream] }
    private struct AudioStream: Decodable { let callSign: String; let url: String }

    static func callSign(in data: Data, matching streamKey: String) -> String? {
        guard let stations = try? JSONDecoder().decode(Response.self, from: data).data?.stations else { return nil }
        return stations.lazy.flatMap(\.audioStreams).first { $0.url.listnrStreamKey == streamKey }?.callSign
    }
}

enum LiSTNRNowPlayingParser {
    private struct Envelope: Decodable { let data: Payload }
    private struct Payload: Decodable { let stations: [Station] }
    private struct Station: Decodable { let currentTrack: Track? }
    private struct Track: Decodable {
        let title: String?
        let artistName: String?
        let albumName: String?
    }

    static func containsStationPayload(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: data).data.stations.first) != nil
    }

    static func evaluate(_ data: Data) -> StreamTrackMetadataEvaluation {
        guard let station = try? JSONDecoder().decode(Envelope.self, from: data).data.stations.first else {
            return StreamTrackMetadataParser.malformedPayloadEvaluation()
        }
        guard let track = station.currentTrack else { return StreamTrackMetadataParser.noCurrentTrackEvaluation() }
        return StreamTrackMetadataParser.evaluate(title: track.title, artist: track.artistName, album: track.albumName)
    }

    static func envelopeDetails(_ data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any] else {
            return ["payloadShape": "invalid-json"]
        }
        let keys = payload.keys.sorted().joined(separator: ",")
        let stationCount = (payload["stations"] as? [Any])?.count ?? 0
        return ["payloadShape": keys.isEmpty ? "empty-data" : keys,
                "stationPayloadCount": "\(stationCount)"]
    }
}

enum ABCNowPlayingParser {
    private struct Response: Decodable {
        let mapiNow: Track?
        let mapiPrev: Track?
        let lastUpdated: String?
        let nextUpdated: String?
        let serverTime: String?
    }
    private struct Track: Decodable {
        let title: String?
        let artist: String?
        let releaseTitle: String?
        let release: Release?
    }
    private struct Release: Decodable { let title: String? }

    static func parse(_ data: Data) -> StreamTrackMetadata? {
        evaluate(data).metadata
    }

    static func evaluate(_ data: Data) -> StreamTrackMetadataEvaluation {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return StreamTrackMetadataParser.malformedPayloadEvaluation()
        }
        var details = [
            "abcCurrentTrackPresent": response.mapiNow == nil ? "false" : "true",
            "abcPreviousTitle": response.mapiPrev?.title ?? "<none>",
            "abcPreviousArtist": response.mapiPrev?.artist ?? "<none>",
            "abcLastUpdated": response.lastUpdated ?? "<none>",
            "abcNextUpdated": response.nextUpdated ?? "<none>",
            "abcServerTime": response.serverTime ?? "<none>"
        ]
        details["payloadShape"] = response.mapiNow == nil ? "mapiNow-null" : "mapiNow-track"
        guard let track = response.mapiNow else {
            return StreamTrackMetadataParser.noCurrentTrackEvaluation().addingProviderDetails(details)
        }
        return StreamTrackMetadataParser.evaluate(
            title: track.title,
            artist: track.artist,
            album: track.releaseTitle ?? track.release?.title,
            blocksSCAAssetMarkers: false
        ).addingProviderDetails(details)
    }
}

enum TritonNowPlayingParser {
    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var properties: [String: String] = [:]
        private var isFirstEvent = true
        private var propertyName: String?
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "nowplaying-info", !properties.isEmpty { isFirstEvent = false }
            guard isFirstEvent, elementName == "property" else { return }
            propertyName = attributeDict["name"]
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard propertyName != nil else { return }
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "property", let propertyName else { return }
            properties[propertyName] = text
            self.propertyName = nil
            text = ""
        }
    }

    static func parse(_ data: Data) -> StreamTrackMetadata? {
        evaluate(data).metadata
    }

    static func evaluate(_ data: Data) -> StreamTrackMetadataEvaluation {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return StreamTrackMetadataParser.malformedPayloadEvaluation() }
        return StreamTrackMetadataParser.evaluate(
            title: delegate.properties["cue_title"],
            artist: delegate.properties["track_artist_name"],
            album: delegate.properties["track_album_name"]
        )
    }
}

@MainActor
final class CompanionMetadataProvider {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let loader: Loader
    private let pollInterval: Duration
    private let heartbeatInterval: TimeInterval
    private let silenceWarningInterval: TimeInterval
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var activeContext: (stationID: String, stationName: String, source: String)?
    private var webSocket: URLSessionWebSocketTask?
    private var listnrMonitorTask: Task<Void, Never>?
    private var listnrTimeline: MetadataDiagnosticTimeline?
    private var listnrLastMessageAt: Date?
    private var listnrConnectionAttempt = 0
    private let listnrInactivityInterval: TimeInterval = 90

    init(
        pollInterval: Duration = .seconds(15),
        heartbeatInterval: TimeInterval = 60,
        silenceWarningInterval: TimeInterval = 120,
        loader: @escaping Loader = { try await URLSession.shared.data(for: $0) }
    ) {
        self.pollInterval = pollInterval
        self.heartbeatInterval = heartbeatInterval
        self.silenceWarningInterval = silenceWarningInterval
        self.loader = loader
    }

    func start(station: DirectoryStation, selectedStreamID: String?, receive: @escaping @MainActor (StreamTrackMetadataEvaluation) -> Void) {
        stop()
        guard let source = CompanionMetadataSource.source(for: station, selectedStreamID: selectedStreamID) else {
            StreamDiagnosticLogger.shared.record("metadata.providerDecision", "Companion metadata unavailable", metadata: [
                "reason": CompanionMetadataSource.unavailableReason(for: station, selectedStreamID: selectedStreamID),
                "stationID": station.id, "stationName": station.name
            ])
            return
        }
        let stationID = station.id
        let stationName = station.name
        let token = UUID()
        generation = token
        listnrConnectionAttempt = 0
        activeContext = (stationID, stationName, source.diagnosticName)
        StreamDiagnosticLogger.shared.record("metadata.providerDecision", "Companion metadata enabled", metadata: [
            "reason": source.enablementReason, "stationID": stationID, "stationName": stationName, "source": source.diagnosticName
        ])
        if case .listnr(let streamKey) = source {
            task = Task { [weak self] in
                await self?.runLiSTNR(streamKey: streamKey, stationID: stationID, stationName: stationName, token: token, receive: receive)
            }
            return
        }
        task = Task { [loader, pollInterval, heartbeatInterval, silenceWarningInterval] in
            var lastMetadata: StreamTrackMetadata?
            var lastEvaluation: StreamTrackMetadataEvaluation?
            var receiptNumber = 0
            var lastError = ""
            var timeline = MetadataDiagnosticTimeline(heartbeatInterval: heartbeatInterval, silenceWarningInterval: silenceWarningInterval)
            StreamDiagnosticLogger.shared.record("metadata.providerStarted", "Companion metadata polling started", metadata: [
                "stationID": stationID, "stationName": stationName, "source": source.diagnosticName
            ])
            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: source.url)
                    request.timeoutInterval = 12
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.setValue("Wireless/1.0", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await loader(request)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    let evaluation = source.evaluate(data)
                    let metadata = evaluation.metadata
                    let now = Date()
                    let elapsed = timeline.record(evaluation, at: now)
                    guard generation == token else { return }
                    receiptNumber += 1
                    let repeated = evaluation.hasSameCandidate(as: lastEvaluation)
                    let trackChanged = metadata != nil && metadata != lastMetadata
                    var fields = evaluation.diagnosticFields
                    fields.merge(elapsed) { _, new in new }
                    fields.merge(source.transportDiagnosticFields) { _, new in new }
                    fields["httpStatus"] = "\(http.statusCode)"
                    fields["responseContentType"] = http.value(forHTTPHeaderField: "Content-Type") ?? "<none>"
                    fields["payloadBytes"] = "\(data.count)"
                    fields["receiptNumber"] = "\(receiptNumber)"
                    fields["repeatedEvaluation"] = "\(repeated)"
                    fields["acceptedTrackChanged"] = "\(trackChanged)"
                    fields["stationID"] = stationID
                    fields["stationName"] = stationName
                    fields["source"] = source.diagnosticName
                    StreamDiagnosticLogger.shared.record("metadata.evaluated", "Companion metadata received and evaluated", metadata: fields)
                    lastEvaluation = evaluation
                    if timeline.successfulHeartbeatDue(at: now) {
                        logHeartbeat(stationID: stationID, stationName: stationName, source: source.diagnosticName, timeline: timeline, reason: "successful-poll", at: now)
                    }
                    logSilenceIfNeeded(stationID: stationID, stationName: stationName, source: source.diagnosticName, timeline: &timeline, at: now)
                    if !lastError.isEmpty {
                        StreamDiagnosticLogger.shared.record("metadata.providerRecovered", "Companion metadata service recovered", metadata: [
                            "stationID": stationID, "stationName": stationName, "source": source.diagnosticName
                        ])
                        lastError = ""
                    }
                    lastMetadata = metadata ?? lastMetadata
                    receive(evaluation)
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                    let description = String(describing: error)
                    if description != lastError {
                        StreamDiagnosticLogger.shared.record("metadata.providerFailed", "Companion metadata request failed", metadata: [
                            "error": description, "stationID": stationID, "stationName": stationName, "source": source.diagnosticName
                        ])
                        lastError = description
                    }
                    // Preserve the current song during a transient network failure.
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func runLiSTNR(
        streamKey: String,
        stationID: String,
        stationName: String,
        token: UUID,
        receive: @escaping @MainActor (StreamTrackMetadataEvaluation) -> Void
    ) async {
        var timeline = MetadataDiagnosticTimeline(heartbeatInterval: heartbeatInterval, silenceWarningInterval: silenceWarningInterval)
        do {
            var components = URLComponents(string: "https://api.listnr.com/v2")!
            components.queryItems = [URLQueryItem(name: "query", value: "query WirelessStations { stations { audioStreams { callSign url } } }")]
            var request = URLRequest(url: components.url!)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (directoryData, response) = try await loader(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let callSign = LiSTNRDirectoryParser.callSign(in: directoryData, matching: streamKey) else {
                StreamDiagnosticLogger.shared.record("metadata.providerUnavailable", "LiSTNR call sign could not be resolved", metadata: [
                    "reason": "official-stream-not-found-in-listnr-directory", "stationID": stationID,
                    "stationName": stationName, "source": "listnr:\(streamKey)"
                ])
                return
            }
            guard generation == token else { return }
            let socket = URLSession.shared.webSocketTask(with: URL(string: "wss://ws.nowplaying.listnr.com/station")!)
            webSocket = socket
            listnrTimeline = timeline
            listnrLastMessageAt = Date()
            listnrConnectionAttempt += 1
            socket.resume()
            let subscription = #"{"action":"Subscribe","payload":{"callSign":"\#(callSign.lowercased())","initialise":true}}"#
            try await socket.send(.string(subscription))
            startLiSTNRMonitor(
                socket: socket,
                stationID: stationID,
                stationName: stationName,
                source: "listnr:\(streamKey)",
                token: token
            )
            StreamDiagnosticLogger.shared.record("metadata.providerStarted", "LiSTNR companion metadata subscribed", metadata: [
                "callSign": callSign, "connectionAttempt": "\(listnrConnectionAttempt)",
                "stationID": stationID, "stationName": stationName, "source": "listnr:\(streamKey)"
            ])
            var receiptNumber = 0
            var lastEvaluation: StreamTrackMetadataEvaluation?
            var lastMetadata: StreamTrackMetadata?
            while !Task.isCancelled, generation == token {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                let now = Date()
                listnrLastMessageAt = now
                _ = timeline.recordContact(at: now)
                listnrTimeline = timeline
                receiptNumber += 1
                var receiptFields = LiSTNRNowPlayingParser.envelopeDetails(data)
                receiptFields.merge([
                    "callSign": callSign, "connectionAttempt": "\(listnrConnectionAttempt)",
                    "payloadBytes": "\(data.count)", "receiptNumber": "\(receiptNumber)",
                    "stationID": stationID, "stationName": stationName, "source": "listnr:\(streamKey)",
                    "transport": "websocket"
                ]) { _, new in new }
                StreamDiagnosticLogger.shared.record("metadata.providerMessage", "LiSTNR WebSocket message received", metadata: receiptFields)
                guard LiSTNRNowPlayingParser.containsStationPayload(data) else {
                    StreamDiagnosticLogger.shared.record("metadata.providerConnected", "LiSTNR companion connection acknowledged", metadata: [
                        "stationID": stationID, "stationName": stationName, "source": "listnr:\(streamKey)"
                    ])
                    continue
                }
                let evaluation = LiSTNRNowPlayingParser.evaluate(data)
                let repeated = evaluation.hasSameCandidate(as: lastEvaluation)
                let trackChanged = evaluation.metadata != nil && evaluation.metadata != lastMetadata
                var fields = evaluation.diagnosticFields
                fields.merge(timeline.record(evaluation, at: now)) { _, new in new }
                listnrTimeline = timeline
                fields.merge(LiSTNRNowPlayingParser.envelopeDetails(data)) { _, new in new }
                fields["callSign"] = callSign
                fields["connectionAttempt"] = "\(listnrConnectionAttempt)"
                fields["payloadBytes"] = "\(data.count)"
                fields["receiptNumber"] = "\(receiptNumber)"
                fields["repeatedEvaluation"] = "\(repeated)"
                fields["acceptedTrackChanged"] = "\(trackChanged)"
                fields["transport"] = "websocket"
                fields["stationID"] = stationID
                fields["stationName"] = stationName
                fields["source"] = "listnr:\(streamKey)"
                StreamDiagnosticLogger.shared.record("metadata.evaluated", "LiSTNR companion metadata evaluated", metadata: fields)
                lastEvaluation = evaluation
                if let metadata = evaluation.metadata { lastMetadata = metadata }
                receive(evaluation)
                if timeline.successfulHeartbeatDue(at: now) {
                    logHeartbeat(stationID: stationID, stationName: stationName, source: "listnr:\(streamKey)", timeline: timeline, reason: "successful-websocket-message", at: now)
                }
                logSilenceIfNeeded(stationID: stationID, stationName: stationName, source: "listnr:\(streamKey)", timeline: &timeline, at: now)
                listnrTimeline = timeline
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            StreamDiagnosticLogger.shared.record("metadata.providerFailed", "LiSTNR companion metadata failed", metadata: [
                "error": String(describing: error), "stationID": stationID, "stationName": stationName, "source": "listnr:\(streamKey)"
            ])
            guard generation == token else { return }
            StreamDiagnosticLogger.shared.record("metadata.providerReconnect", "LiSTNR companion metadata will reconnect", metadata: [
                "reason": "connection-ended", "stationID": stationID, "stationName": stationName, "source": "listnr:\(streamKey)"
            ])
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, generation == token else { return }
            await runLiSTNR(streamKey: streamKey, stationID: stationID, stationName: stationName, token: token, receive: receive)
        }
    }

    private func startLiSTNRMonitor(socket: URLSessionWebSocketTask, stationID: String, stationName: String, source: String, token: UUID) {
        listnrMonitorTask?.cancel()
        listnrMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == token {
                try? await Task.sleep(for: .seconds(self.heartbeatInterval))
                guard !Task.isCancelled, self.generation == token else { return }
                guard socket.state == .running, var timeline = self.listnrTimeline else { continue }
                let now = Date()
                let messageElapsed = now.timeIntervalSince(self.listnrLastMessageAt ?? now)
                if messageElapsed >= self.listnrInactivityInterval {
                    var fields = timeline.elapsedFields(at: now)
                    fields.merge([
                        "lastServerMessageElapsedSeconds": String(format: "%.1f", messageElapsed),
                        "reason": "websocket-message-inactivity", "stationID": stationID,
                        "stationName": stationName, "source": source
                    ]) { _, new in new }
                    StreamDiagnosticLogger.shared.record("metadata.providerStale", "LiSTNR connection received no server messages", metadata: fields)
                    socket.cancel(with: .goingAway, reason: Data("metadata-inactivity".utf8))
                    return
                }
                self.logHeartbeat(stationID: stationID, stationName: stationName, source: source, timeline: timeline, reason: "websocket-open", at: now, extra: [
                    "lastServerMessageElapsedSeconds": String(format: "%.1f", messageElapsed)
                ])
                self.logSilenceIfNeeded(stationID: stationID, stationName: stationName, source: source, timeline: &timeline, at: now)
                self.listnrTimeline = timeline
            }
        }
    }

    private func logHeartbeat(stationID: String, stationName: String, source: String, timeline: MetadataDiagnosticTimeline, reason: String, at now: Date, extra: [String: String] = [:]) {
        var fields = timeline.elapsedFields(at: now)
        fields.merge(["reason": reason, "stationID": stationID, "stationName": stationName, "source": source]) { _, new in new }
        fields.merge(extra) { _, new in new }
        let message = reason == "websocket-open" ? "Companion metadata WebSocket remains open" : "Companion metadata provider poll succeeded"
        StreamDiagnosticLogger.shared.record("metadata.providerHeartbeat", message, metadata: fields)
    }

    private func logSilenceIfNeeded(stationID: String, stationName: String, source: String, timeline: inout MetadataDiagnosticTimeline, at now: Date) {
        guard let warning = timeline.silenceWarningDue(at: now) else { return }
        var fields = timeline.elapsedFields(at: now)
        fields.merge([
            "affectsDisplay": "true", "preferredSource": "companion",
            "reason": "no-usable-song-metadata", "silenceWarningNumber": "\(warning.number)",
            "stationID": stationID, "stationName": stationName, "source": source
        ]) { _, new in new }
        StreamDiagnosticLogger.shared.record("metadata.silence", "No usable song metadata has been accepted", metadata: fields)
    }

    func stop() {
        if let activeContext {
            StreamDiagnosticLogger.shared.record("metadata.providerStopped", "Companion metadata polling stopped", metadata: [
                "stationID": activeContext.stationID, "stationName": activeContext.stationName, "source": activeContext.source
            ])
        }
        activeContext = nil
        listnrMonitorTask?.cancel()
        listnrMonitorTask = nil
        listnrTimeline = nil
        listnrLastMessageAt = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        generation = UUID()
        task?.cancel()
        task = nil
    }
}

private extension CompanionMetadataSource {
    var enablementReason: String {
        switch self {
        case .abc: "official-abc-music-now-playing"
        case .triton: "streamtheworld-mount-detected"
        case .listnr: "music-focused-official-listnr-stream-detected"
        }
    }

    var transportDiagnosticFields: [String: String] {
        switch self {
        case .abc(let serviceID):
            return ["transport": "https-poll", "providerServiceID": serviceID,
                    "endpointHost": url.host ?? "<none>", "endpointPath": url.path]
        case .triton(let mountName):
            return ["transport": "https-poll", "providerServiceID": mountName,
                    "endpointHost": url.host ?? "<none>", "endpointPath": url.path]
        case .listnr(let streamKey):
            return ["transport": "websocket", "providerServiceID": streamKey,
                    "endpointHost": "ws.nowplaying.listnr.com", "endpointPath": "/station"]
        }
    }
}

private extension DirectoryStation {
    var isMusicFocused: Bool {
        guard let genre = music_genre?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty else { return false }
        return !["News", "Sport", "Not yet categorised"].contains {
            genre.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    var prefersEmbeddedSCABroadcastMetadata: Bool {
        let isBroadcastNetwork = network.caseInsensitiveCompare("Triple M") == .orderedSame
            || network.caseInsensitiveCompare("Hit Network") == .orderedSame
            || network.caseInsensitiveCompare("Hit") == .orderedSame
        guard isBroadcastNetwork else { return false }
        guard let subnetwork = subnetwork?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            // A missing classification is safer on the embedded path: enabling
            // LiSTNR from the stream host alone recreated the original fault.
            return true
        }
        return subnetwork.caseInsensitiveCompare("Music") != .orderedSame
    }
}

private extension StationStream {
    var tritonMountName: String? {
        guard let url = playableURL,
              url.host?.caseInsensitiveCompare("playerservices.streamtheworld.com") == .orderedSame,
              url.pathComponents.contains("livestream-redirect") else { return nil }
        var mount = url.deletingPathExtension().lastPathComponent
        mount = mount.replacingOccurrences(
            of: #"_(?:AAC|MP3)\d*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return mount.isEmpty ? nil : mount.uppercased()
    }
}

private extension StationStream {
    var listnrStreamKey: String? { url.listnrStreamKey }
}

private extension String {
    var listnrStreamKey: String? {
        guard let url = URL(string: self), url.host?.localizedCaseInsensitiveContains("scastream.com.au") == true else { return nil }
        let component = url.pathComponents.first { $0.lowercased().hasSuffix(".stream") }
        guard let component else { return nil }
        return component.replacingOccurrences(of: ".stream", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: #"_128$"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
