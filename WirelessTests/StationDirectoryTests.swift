import XCTest

final class StationDirectoryTests: XCTestCase {
    @MainActor func testFavouritesPersistAndMigrateAnExplicitRemoval() throws {
        let suite = "StationLibraryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(false, forKey: "senFavourite")
        let first = StationLibrary(defaults: defaults, cacheURL: cache)
        XCTAssertTrue(first.favourites.isEmpty)
        first.toggle(.sen)
        let second = StationLibrary(defaults: defaults, cacheURL: cache)
        XCTAssertEqual(second.favourites.map(\.id), [DirectoryStation.sen.id])
        second.toggle(.sen)
        XCTAssertTrue(StationLibrary(defaults: defaults, cacheURL: cache).favourites.isEmpty)
    }
    @MainActor func testFavouriteReorderPersistsAndControlsDisplayOrder() throws {
        let suite = "StationLibraryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "senFavourite")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = StationLibrary(defaults: defaults, cacheURL: cache)
        let alpha = DirectoryStation(id: "alpha", name: "Alpha", network: "", country: "AU", state: "", cities: [], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        let bravo = DirectoryStation(id: "bravo", name: "Bravo", network: "", country: "AU", state: "", cities: [], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        first.toggle(alpha)
        first.toggle(bravo)
        first.moveFavourites(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(first.results(favouritesOnly: true, query: "", network: "", city: "").map(\.id), ["bravo", "alpha"])
        XCTAssertEqual(StationLibrary(defaults: defaults, cacheURL: cache).favourites.map(\.id), ["bravo", "alpha"])
    }
    @MainActor func testOfflineCacheSearchAndFilters() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let snapshot = CatalogueSnapshot(revision: 5, date: Date(), stations: [.sen])
        try JSONEncoder().encode(snapshot).write(to: cache)
        let library = StationLibrary(cacheURL: cache)
        XCTAssertNotNil(library.refreshedAt)
        XCTAssertEqual(library.results(favouritesOnly: false, query: "melbourne", network: "SEN", city: "Melbourne").count, 1)
        XCTAssertTrue(library.results(favouritesOnly: false, query: "", network: "ABC", city: "").isEmpty)
    }
    @MainActor func testFailedRefreshKeepsCachedStationsAndFavourites() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "StationLibraryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: cache); defaults.removePersistentDomain(forName: suite) }
        try JSONEncoder().encode(CatalogueSnapshot(revision: 1, date: Date(), stations: [.sen])).write(to: cache)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineProtocol.self]
        let library = StationLibrary(defaults: defaults, cacheURL: cache, client: CatalogueClient(session: URLSession(configuration: config)))
        library.toggle(.sen)
        await library.refresh()
        XCTAssertNotNil(library.error)
        XCTAssertFalse(library.isLoading)
        XCTAssertEqual(library.stations.map(\.id), [DirectoryStation.sen.id])
        XCTAssertTrue(library.contains(.sen))
    }

    func testPreferredStreamFallsBackFromUnsupportedFormatAndRejectsUnsafeURL() {
        let unsupported = StationStream(id: "ogg", url: "https://example.com/audio", label: "", format: "ogg", codec: "vorbis", bitrate_kbps: nil, request_headers: [:])
        let invalid = StationStream(id: "file", url: "file:///tmp/audio.mp3", label: "", format: "mp3", codec: "", bitrate_kbps: nil, request_headers: [:])
        let sen = DirectoryStation.sen
        let station = DirectoryStation(id: "test", name: "Test", network: "", country: "AU", state: "", cities: [], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: unsupported.id, streams: [unsupported, invalid] + sen.streams)
        XCTAssertEqual(station.preferredStream?.id, "sen-hls")
        XCTAssertEqual(station.playableStreams.count, 2)
    }
    func testLiveDirectoryDownloadsEveryPageWithoutDuplicateIDs() async throws {
        guard ProcessInfo.processInfo.environment["WIRELESS_LIVE_DIRECTORY_TESTS"] == "1" else {
            throw XCTSkip("Set WIRELESS_LIVE_DIRECTORY_TESTS=1 in the test scheme to check the live service.")
        }
        let snapshot = try await CatalogueClient().fetch()
        XCTAssertGreaterThan(snapshot.stations.count, 1000)
        XCTAssertEqual(Set(snapshot.stations.map(\.id)).count, snapshot.stations.count)
        XCTAssertTrue(snapshot.stations.contains { $0.id == DirectoryStation.sen.id })
    }
}

private final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
