import XCTest

@MainActor
final class WirelessListeningStatsTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for url in temporaryDirectories { try? FileManager.default.removeItem(at: url) }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testRenderedAudioIsAttributedByStationModeRouteAndSession() throws {
        let store = makeStore()
        let station = makeStation(id: "station-a", name: "Station A")
        let endedAt = try date("2026-10-21T10:00:10+11:00")

        store.recordRendered(seconds: 10, station: station, mode: .live, route: .thisDevice, endedAt: endedAt)
        store.recordRendered(seconds: 5, station: station, mode: .vocalBoost, route: .bluetooth, endedAt: endedAt.addingTimeInterval(5))

        var summary = store.summary(for: .lifetime)
        XCTAssertEqual(summary.listeningSeconds, 15, accuracy: 0.001)
        XCTAssertEqual(summary.perStationSeconds[station.id] ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(summary.modeSeconds[WirelessListeningMode.live.rawValue] ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(summary.modeSeconds[WirelessListeningMode.vocalBoost.rawValue] ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(summary.routeSeconds[WirelessAudioRouteCategory.thisDevice.rawValue] ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(summary.routeSeconds[WirelessAudioRouteCategory.bluetooth.rawValue] ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.longestSessionSeconds, 15, accuracy: 0.001)

        store.endSession()
        store.recordRendered(seconds: 3, station: station, mode: .tvSync, route: .airPlay, endedAt: endedAt.addingTimeInterval(20))
        summary = store.summary(for: .lifetime)
        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.averageSessionSeconds, 9, accuracy: 0.001)
    }

    func testRenderedIntervalSplitsAcrossLocalMidnightAndHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Melbourne"))
        let store = makeStore(calendar: calendar)
        let station = makeStation(id: "station-midnight", name: "Midnight Radio")
        let endedAt = try date("2026-10-22T00:00:05+11:00")

        store.recordRendered(seconds: 10, station: station, mode: .live, route: .thisDevice, endedAt: endedAt)

        let summary = store.summary(for: .lifetime)
        XCTAssertEqual(summary.days.count, 2)
        XCTAssertEqual(summary.days.first(where: { $0.dayKey == "2026-10-21" })?.hourSeconds[23] ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(summary.days.first(where: { $0.dayKey == "2026-10-22" })?.hourSeconds[0] ?? -1, 5, accuracy: 0.001)
    }

    func testStationChangeStartsAnotherSession() throws {
        let store = makeStore()
        let first = makeStation(id: "first", name: "First")
        let second = makeStation(id: "second", name: "Second")
        let time = try date("2026-10-21T12:00:00+11:00")

        store.recordRendered(seconds: 4, station: first, mode: .live, route: .thisDevice, endedAt: time)
        store.recordRendered(seconds: 6, station: second, mode: .live, route: .thisDevice, endedAt: time.addingTimeInterval(6))

        let summary = store.summary(for: .lifetime)
        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.stationCount, 2)
    }

    func testListeningHistoryUsesOneMinuteEligibilityForRowsAndCards() throws {
        let store = makeStore()
        let short = makeStation(id: "short", name: "Short Listen")
        let eligible = makeStation(id: "eligible", name: "History Station")
        let time = try date("2026-10-21T12:00:00+11:00")

        store.recordRendered(seconds: 59, station: short, mode: .live, route: .thisDevice, endedAt: time)
        store.endSession()
        store.recordRendered(seconds: 60, station: eligible, mode: .live, route: .thisDevice, endedAt: time.addingTimeInterval(120))

        let history = store.listeningHistory()
        XCTAssertEqual(history.sessionCount, 1)
        XCTAssertEqual(history.listeningSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(history.items.first?.station.name, "History Station")
        XCTAssertEqual(history.items.first?.session.stationID, eligible.id)
    }

    func testOlderSessionJSONDecodesWithoutAnEndReason() throws {
        let json = """
        {
          "id": "legacy-session",
          "stationID": "station-a",
          "startedAt": "2026-10-21T00:00:00Z",
          "endedAt": "2026-10-21T00:01:00Z",
          "renderedSeconds": 60
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(WirelessListeningSession.self, from: Data(json.utf8))

        XCTAssertNil(session.endReason)
        XCTAssertTrue(session.isHistoryEligible)
    }

    func testListeningHistoryCreatesANewRowAfterPauseAndResume() throws {
        let store = makeStore()
        let station = makeStation(id: "station-a", name: "Station A")
        let time = try date("2026-10-21T12:00:00+11:00")

        store.recordRendered(seconds: 60, station: station, mode: .live, route: .thisDevice, endedAt: time)
        let firstSessionID = try XCTUnwrap(store.activeSessionID)
        store.endSession(reason: .paused)
        store.recordRendered(seconds: 60, station: station, mode: .live, route: .thisDevice, endedAt: time.addingTimeInterval(120))

        let history = store.listeningHistory()
        XCTAssertEqual(history.sessionCount, 2)
        XCTAssertNotEqual(store.activeSessionID, firstSessionID)
        XCTAssertEqual(history.items.last?.session.endReason, .paused)
        XCTAssertNil(history.items.first?.session.endReason)
    }

    func testListeningHistoryOrdersCrossMidnightSessionByLatestHeardTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Melbourne"))
        let store = makeStore(calendar: calendar)
        let station = makeStation(id: "overnight", name: "Overnight Radio")
        let endedAt = try date("2026-10-22T00:00:30+11:00")

        store.recordRendered(seconds: 90, station: station, mode: .live, route: .thisDevice, endedAt: endedAt)

        let item = try XCTUnwrap(store.listeningHistory().items.first)
        XCTAssertEqual(item.session.startedAt, endedAt.addingTimeInterval(-90))
        XCTAssertEqual(item.session.endedAt, endedAt)
        XCTAssertEqual(item.session.renderedSeconds, 90, accuracy: 0.001)
    }

    func testDetailedHistoryPruningKeepsAggregateListeningTotals() throws {
        let store = makeStore()
        let station = makeStation(id: "long-term", name: "Long-term Station")
        let start = try date("2020-01-01T00:00:00Z")
        let sessionCount = WirelessListeningStatsStore.detailedSessionLimit + 1

        for index in 0..<sessionCount {
            store.recordRendered(
                seconds: 60,
                station: station,
                mode: .live,
                route: .thisDevice,
                endedAt: start.addingTimeInterval(Double(index * 120))
            )
            store.endSession()
        }

        XCTAssertEqual(store.listeningHistory().sessionCount, WirelessListeningStatsStore.detailedSessionLimit)
        XCTAssertEqual(
            store.summary(for: .lifetime).listeningSeconds,
            Double(sessionCount * 60),
            accuracy: 0.001
        )
    }

    func testPrimaryCorruptionRecoversLastKnownGoodBackup() throws {
        let file = temporaryFile()
        let station = makeStation(id: "station-a", name: "Station A")
        let time = try date("2026-10-21T12:00:00+11:00")
        var store: WirelessListeningStatsStore? = WirelessListeningStatsStore(fileURL: file, protectedDataAvailable: { true })
        store?.recordRendered(seconds: 10, station: station, mode: .live, route: .thisDevice, endedAt: time)
        store?.checkpoint()
        store?.recordRendered(seconds: 5, station: station, mode: .live, route: .thisDevice, endedAt: time.addingTimeInterval(5))
        store?.checkpoint()
        store = nil
        try Data("damaged".utf8).write(to: file, options: .atomic)

        let recovered = WirelessListeningStatsStore(fileURL: file, protectedDataAvailable: { true })
        XCTAssertEqual(recovered.loadState, .recoveredBackup)
        XCTAssertEqual(recovered.summary(for: .lifetime).listeningSeconds, 10, accuracy: 0.001)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .contains { $0.lastPathComponent.hasPrefix("listening-stats.corrupt-") })
    }

    func testInvalidPrimaryWithoutBackupCannotBeOverwritten() throws {
        let file = temporaryFile()
        try Data("damaged".utf8).write(to: file, options: .atomic)
        let store = WirelessListeningStatsStore(fileURL: file, protectedDataAvailable: { true })
        XCTAssertEqual(store.loadState, .failed)

        store.recordRendered(
            seconds: 30,
            station: makeStation(id: "station-a", name: "Station A"),
            mode: .live,
            route: .thisDevice
        )
        store.checkpoint()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.summary(for: .lifetime).listeningSeconds, 0)
    }

    func testJSONImportIsIdempotent() throws {
        let source = makeStore()
        source.recordRendered(
            seconds: 45,
            station: makeStation(id: "station-a", name: "Station A"),
            mode: .live,
            route: .thisDevice,
            endedAt: try date("2026-10-21T12:00:00+11:00")
        )
        let archive = try source.makeJSONExport()
        let destination = makeStore()

        try destination.importJSON(from: archive)
        try destination.importJSON(from: archive)

        XCTAssertEqual(destination.summary(for: .lifetime).listeningSeconds, 45, accuracy: 0.001)
    }

    private func makeStore(calendar: Calendar = .current) -> WirelessListeningStatsStore {
        WirelessListeningStatsStore(
            fileURL: temporaryFile(),
            calendarProvider: { calendar },
            protectedDataAvailable: { true }
        )
    }

    private func temporaryFile() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wireless-stats-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("listening-stats.json")
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func makeStation(id: String, name: String) -> DirectoryStation {
        DirectoryStation(
            id: id,
            name: name,
            network: "Network",
            country: "AU",
            state: "VIC",
            cities: ["Melbourne"],
            tags: ["Music"],
            description: "",
            website_url: "",
            logo_url: "https://example.com/logo.png",
            preferred_stream_id: nil,
            streams: []
        )
    }
}
