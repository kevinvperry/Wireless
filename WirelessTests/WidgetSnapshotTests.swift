import XCTest

final class WidgetSnapshotTests: XCTestCase {
    private func station(_ id: String) -> WidgetDisplayStation {
        WidgetDisplayStation(id: id, name: id, subtitle: "Radio", thumbnailFilename: nil)
    }
    func testSelectedStationDoesNotDuplicateRankedFavourites() {
        let snapshot = WidgetSnapshot(schemaVersion: 1, generatedAt: Date(), current: station("b"),
            favourites: [station("a"), station("b"), station("c")], isPlaying: false)
        XCTAssertEqual(snapshot.primary?.id, "b")
        XCTAssertEqual(snapshot.following.map(\.id), ["a", "c"])
    }
    func testFirstFavouriteIsPrimaryBeforeAStationIsSelected() {
        let snapshot = WidgetSnapshot(schemaVersion: 1, generatedAt: Date(), current: nil,
            favourites: [station("a"), station("b")], isPlaying: false)
        XCTAssertEqual(snapshot.primary?.id, "a")
        XCTAssertEqual(snapshot.following.map(\.id), ["b"])
    }
    func testSnapshotRoundTripAndInvalidSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = WidgetSharedStorage(containerURL: directory)
        let snapshot = WidgetSnapshot(schemaVersion: 1, generatedAt: Date(timeIntervalSince1970: 100),
            current: station("a"), favourites: [], isPlaying: true)
        try storage.write(snapshot)
        XCTAssertEqual(try storage.read(), snapshot)
        XCTAssertThrowsError(try storage.thumbnailURL(filename: "../escape.png"))
        let invalid = WidgetSnapshot(schemaVersion: 99, generatedAt: Date(), current: nil,
            favourites: [], isPlaying: false)
        XCTAssertThrowsError(try storage.write(invalid))
        XCTAssertEqual(try storage.read(), snapshot)
    }
}
