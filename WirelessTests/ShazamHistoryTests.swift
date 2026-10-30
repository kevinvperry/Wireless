import XCTest

final class ShazamHistoryTests: XCTestCase {
    @MainActor func testRoundTripKeepsMetadataLinksStationAndNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let song = RecognisedSong(title: "My Sharona", artist: "The Knack",
            artworkURL: URL(string: "https://example.com/cover.jpg"), appleMusicURL: URL(string: "https://music.apple.com/au/song/1"),
            shazamURL: URL(string: "https://www.shazam.com/track/1"), shazamID: "1", confidence: 1)
        let store = ShazamHistoryStore(fileURL: file)
        XCTAssertTrue(store.record(song, stationID: "one", stationName: "Station One", at: Date(timeIntervalSince1970: 10)))
        XCTAssertTrue(store.record(song, stationID: "two", stationName: "Station Two", at: Date(timeIntervalSince1970: 20)))
        let restored = ShazamHistoryStore(fileURL: file)
        XCTAssertEqual(restored.entries.count, 2, "Separate identifications remain distinct events")
        XCTAssertEqual(restored.entries.map(\.stationID), ["two", "one"])
        XCTAssertEqual(restored.entries[0].song, song)
        XCTAssertNil(restored.persistenceError)
        let id = restored.entries[0].id
        XCTAssertTrue(restored.record(song, stationID: "two", stationName: "Station Two", id: id))
        XCTAssertEqual(restored.entries.count, 2, "Duplicate callback identity must not add another row")
        XCTAssertTrue(restored.remove(id))
        XCTAssertEqual(ShazamHistoryStore(fileURL: file).entries.count, 1)
        XCTAssertTrue(restored.clear())
        XCTAssertTrue(ShazamHistoryStore(fileURL: file).entries.isEmpty)
    }
    @MainActor func testUnreadableHistoryIsPreservedUntilExplicitClear() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("not valid history".utf8)
        try original.write(to: file)
        let store = ShazamHistoryStore(fileURL: file)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertFalse(store.record(RecognisedSong(title: "Song", artist: "Artist"), stationID: "id", stationName: "Station"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(store.clear())
        XCTAssertNil(store.persistenceError)
        XCTAssertTrue(store.record(RecognisedSong(title: "Song", artist: "Artist"), stationID: "id", stationName: "Station"))
    }
    @MainActor func testFailedLoadRetriesWithoutOverwritingRecoveredEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let song = RecognisedSong(title: "Original", artist: "Artist")
        XCTAssertTrue(ShazamHistoryStore(fileURL: file).record(song, stationID: "one", stationName: "Station One"))
        let valid = try Data(contentsOf: file)
        try Data("unreadable document".utf8).write(to: file)
        let store = ShazamHistoryStore(fileURL: file)
        XCTAssertNotNil(store.persistenceError)
        try valid.write(to: file)
        XCTAssertTrue(store.record(RecognisedSong(title: "New", artist: "Artist"), stationID: "two", stationName: "Station Two"))
        XCTAssertEqual(Set(store.entries.map { $0.song.title }), ["Original", "New"])
        XCTAssertNil(store.persistenceError)
    }
    @MainActor func testFailedWriteDoesNotPretendToSaveOrDeleteHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShazamHistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let song = RecognisedSong(title: "Song", artist: "Artist")
        XCTAssertTrue(store.record(song, stationID: "id", stationName: "Station"))
        let saved = store.entries
        try FileManager.default.removeItem(at: root)
        try Data("file blocks the directory".utf8).write(to: root)
        XCTAssertFalse(store.remove(saved[0].id))
        XCTAssertEqual(store.entries, saved)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertFalse(store.record(song, stationID: "another", stationName: "Another"))
        XCTAssertEqual(store.entries, saved)
    }
}
