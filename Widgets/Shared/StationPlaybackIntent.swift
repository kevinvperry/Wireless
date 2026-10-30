import AppIntents

/// Both targets compile this declaration. AudioPlaybackIntent executes in the app.
struct StationPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Control Wireless Playback"
    static let description = IntentDescription("Plays or pauses a Wireless station.")
    static let isDiscoverable = false
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Station ID") var stationID: String
    @Parameter(title: "Play") var shouldPlay: Bool

    init() { stationID = ""; shouldPlay = true }
    init(stationID: String, shouldPlay: Bool) {
        self.stationID = stationID
        self.shouldPlay = shouldPlay
    }
    @MainActor
    func perform() async throws -> some IntentResult {
        await controlPlayback()
        return .result()
    }
}
