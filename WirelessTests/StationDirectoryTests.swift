import XCTest

final class StationDirectoryTests: XCTestCase {
    func testStationDecodesRegionMetadataAndKeepsOlderCachedRecordsCompatible() throws {
        let current = """
        {"id":"test","name":"Test Radio","network":"Test Network","country":"AU","state":"VIC","cities":["Melbourne"],"tags":[],"frequency":"101.1 FM","metro_regional":"Metro","description":"","website_url":"","logo_url":"","preferred_stream_id":null,"streams":[]}
        """.data(using: .utf8)!
        let station = try JSONDecoder().decode(DirectoryStation.self, from: current)
        XCTAssertEqual(station.frequency, "101.1 FM")
        XCTAssertEqual(station.metro_regional, "Metro")

        var legacy = try JSONSerialization.jsonObject(with: current) as! [String: Any]
        legacy.removeValue(forKey: "metro_regional")
        XCTAssertNil(try JSONDecoder().decode(DirectoryStation.self, from: JSONSerialization.data(withJSONObject: legacy)).metro_regional)
    }

    func testSydneyRatingsAndAlphabeticalRemainderOrganisation() {
        func station(_ id: String, _ name: String) -> DirectoryStation {
            DirectoryStation(id: id, name: name, network: "", country: "AU", state: "New South Wales", cities: ["Sydney"], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [
            station("station_612f55de42a8", "SEN 1170"),
            station("station_44dd138bd4c1", "2GB"),
            station("station_2a1af692c272", "Smooth FM 95.3"),
            station("other-z", "Zoo FM"),
            station("other-a", "Alpha Radio"),
            station("other-number", "2XX")
        ]

        XCTAssertEqual(
            StationListOrganisation.topRatingStations(for: "Sydney", from: entries).map(\.id),
            ["station_2a1af692c272", "station_44dd138bd4c1", "station_612f55de42a8"]
        )
        let sections = StationListOrganisation.alphabeticalSections(
            from: StationListOrganisation.excludingTopRatings(for: "Sydney", from: entries)
        )
        XCTAssertEqual(sections.map(\.title), ["A", "Z", "#"])
        XCTAssertEqual(sections.flatMap(\.stations).map(\.name), ["Alpha Radio", "Zoo FM", "2XX"])
    }

    func testMelbourneRatingsOrganisationUsesAudienceShareOrder() {
        func station(_ id: String, _ name: String) -> DirectoryStation {
            DirectoryStation(id: id, name: name, network: "", country: "AU", state: "Victoria", cities: ["Melbourne"], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [
            station("station_de2e44c4f0a8", "3MP"),
            station("station_57fa9c360020", "Smooth FM 91.5"),
            station("station_47cd29da5a1d", "3AW Melbourne"),
            station("station_dbbb4ad7c472", "GOLD104.3"),
            station("other", "Alphabet Radio")
        ]

        XCTAssertEqual(
            StationListOrganisation.topRatingStations(for: "Melbourne", from: entries).map(\.id),
            ["station_47cd29da5a1d", "station_dbbb4ad7c472", "station_57fa9c360020", "station_de2e44c4f0a8"]
        )
        XCTAssertEqual(
            StationListOrganisation.excludingTopRatings(for: "Melbourne", from: entries).map(\.id),
            ["other"]
        )
    }

    func testBrisbaneRatingsOrganisationUsesAudienceShareOrder() {
        func station(_ id: String, _ name: String) -> DirectoryStation {
            DirectoryStation(id: id, name: name, network: "", country: "AU", state: "Queensland", cities: ["Brisbane"], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [
            station("station_7ea2e37443b4", "SENQ"),
            station("station_db432bcf4c61", "4BC Brisbane"),
            station("station_5dd9ed2d5c6f", "4BH"),
            station("station_7769426de525", "Triple M Brisbane 104.5"),
            station("other", "Brisbane Community Radio")
        ]

        XCTAssertEqual(
            StationListOrganisation.topRatingStations(for: "Brisbane", from: entries).map(\.id),
            ["station_7769426de525", "station_5dd9ed2d5c6f", "station_db432bcf4c61", "station_7ea2e37443b4"]
        )
        XCTAssertEqual(
            StationListOrganisation.excludingTopRatings(for: "Brisbane", from: entries).map(\.id),
            ["other"]
        )
    }

    func testAdelaideRatingsOrganisationUsesAudienceShareOrder() {
        func station(_ id: String, _ name: String) -> DirectoryStation {
            DirectoryStation(id: id, name: name, network: "", country: "AU", state: "South Australia", cities: ["Adelaide"], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [
            station("station_398cd83cda2e", "GOLD1323"),
            station("station_78ff85cace99", "FIVEAA"),
            station("station_e203995c549d", "Nova 919"),
            station("station_1f72e1b25208", "Triple M Adelaide 104.7"),
            station("other", "Adelaide Community Radio")
        ]

        XCTAssertEqual(
            StationListOrganisation.topRatingStations(for: "Adelaide", from: entries).map(\.id),
            ["station_1f72e1b25208", "station_e203995c549d", "station_78ff85cace99", "station_398cd83cda2e"]
        )
        XCTAssertEqual(
            StationListOrganisation.excludingTopRatings(for: "Adelaide", from: entries).map(\.id),
            ["other"]
        )
    }

    func testPerthRatingsOrganisationUsesAudienceShareOrder() {
        func station(_ id: String, _ name: String) -> DirectoryStation {
            DirectoryStation(id: id, name: name, network: "", country: "AU", state: "Western Australia", cities: ["Perth"], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [
            station("station_1b89f545bcf2", "ABC Perth"),
            station("station_31d448ef0a80", "6iX"),
            station("station_b9975bdb69f2", "GOLD 96FM"),
            station("station_3f29cc24820d", "6PR Perth"),
            station("station_cf0ceecd6c57", "Mix94.5 Perth"),
            station("station_b8bbb3631e74", "Triple M Perth 92.9"),
            station("station_cae7a9815bba", "Nova 93.7"),
            station("other", "Perth Community Radio")
        ]

        XCTAssertEqual(
            StationListOrganisation.topRatingStations(for: "Perth", from: entries).map(\.id),
            ["station_cae7a9815bba", "station_b8bbb3631e74", "station_cf0ceecd6c57", "station_b9975bdb69f2", "station_3f29cc24820d", "station_31d448ef0a80", "station_1b89f545bcf2"]
        )
        XCTAssertEqual(
            StationListOrganisation.excludingTopRatings(for: "Perth", from: entries).map(\.id),
            ["other"]
        )
    }

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

    @MainActor func testMusicGenresRoundTripAndFilterOfflineAcrossNetworks() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        func station(_ id: String, _ network: String, _ genre: String?, browseGenres: [String] = []) -> DirectoryStation {
            DirectoryStation(id: id, name: id, network: network, country: "AU", state: "Victoria", cities: [], tags: [], music_genre: genre, browse_genres: browseGenres, description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        let entries = [station("Alpha", "A", "Rock"), station("Bravo", "B", "Rock"), station("Charlie", "A", "Country"), station("Bunnings Tradio", "D", "Tradie", browseGenres: ["Retail"]), station("Unclassified", "A", nil)]
        try JSONEncoder().encode(CatalogueSnapshot(revision: 1, date: Date(), stations: entries)).write(to: cache)
        let library = StationLibrary(cacheURL: cache)
        XCTAssertEqual(library.musicGenres, ["Country", "Retail", "Rock", "Tradie"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: "Rock").map(\.id), ["Alpha", "Bravo"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "", network: "B", city: "", musicGenre: "Rock").map(\.id), ["Bravo"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "Bravo", network: "", city: "", musicGenre: "Rock").map(\.id), ["Bravo"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "country", network: "", city: "").map(\.id), ["Charlie"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: "Retail").map(\.id), ["Bunnings Tradio"])
        XCTAssertEqual(library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: "Tradie").map(\.id), ["Bunnings Tradio"])
        XCTAssertTrue(library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: "Unknown").isEmpty)
        var oldRecord = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries[0])) as! [String: Any]
        oldRecord.removeValue(forKey: "music_genre")
        XCTAssertNil(try JSONDecoder().decode(DirectoryStation.self, from: JSONSerialization.data(withJSONObject: oldRecord)).music_genre)
    }

    @MainActor func testNavigatingDuringRefreshSharesWorkDespiteCancelledCaller() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GenreRefreshProtocol.self]
        let library = StationLibrary(cacheURL: cache, client: CatalogueClient(session: URLSession(configuration: config)))
        let departingView = Task { await library.refresh() }
        try await Task.sleep(nanoseconds: 20_000_000)
        departingView.cancel()
        await library.refresh()
        XCTAssertNil(library.error)
        XCTAssertFalse(library.isLoading)
        XCTAssertEqual(library.musicGenres, ["Rock"])
        XCTAssertEqual(StationLibrary(cacheURL: cache).musicGenres, ["Rock"])
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

private final class GenreRefreshProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
            var station = DirectoryStation.sen
            station.music_genre = "Rock"
            let payload: [String: Any]
            if request.url?.path.hasSuffix("/api/v1/networks") == true {
                payload = ["schema_version": 1, "revision": 99, "networks": []]
            } else {
                let record = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(station))
                payload = ["schema_version": 1, "revision": 99, "page": 1, "total": 1, "has_more": false, "stations": [record]]
            }
            let data = try! JSONSerialization.data(withJSONObject: payload)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
