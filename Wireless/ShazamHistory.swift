import Foundation
import Combine

struct ShazamHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let song: RecognisedSong
    let stationID: String
    let stationName: String
    let identifiedAt: Date
}

/// Adapted from Autohop's main-actor ListeningHistoryStore ownership and atomic
/// Application Support persistence. Recognition history has no playback/sync duties.
@MainActor final class ShazamHistoryStore: ObservableObject {
    static let shared = ShazamHistoryStore()
    @Published private(set) var entries: [ShazamHistoryEntry] = []
    @Published private(set) var persistenceError: String?
    private let fileURL: URL
    private var loadBlocked = false
    private struct Document: Codable { let version: Int; let entries: [ShazamHistoryEntry] }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wireless/shazam-history.json")
        load()
    }
    func retryLoading() { if loadBlocked { load() } }
    private func load() {
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: self.fileURL))
            guard document.version == 1 else { throw CocoaError(.fileReadUnknown) }
            entries = document.entries.sorted { $0.identifiedAt > $1.identifiedAt }
            loadBlocked = false; persistenceError = nil
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) {
                entries = []; loadBlocked = false; persistenceError = nil; return
            }
            loadBlocked = true
            persistenceError = "Shazam History could not be opened. Existing history has been preserved; new identifications cannot be saved. You can clear history to start again."
        }
    }
    @discardableResult func record(_ song: RecognisedSong, stationID: String, stationName: String,
                                   at date: Date = Date(), id: UUID = UUID()) -> Bool {
        retryLoading()
        guard !loadBlocked else { return false }
        guard !entries.contains(where: { $0.id == id }) else { return true }
        let entry = ShazamHistoryEntry(id: id, song: song, stationID: stationID, stationName: stationName, identifiedAt: date)
        return commit((entries + [entry]).sorted { $0.identifiedAt > $1.identifiedAt })
    }
    @discardableResult func remove(_ id: UUID) -> Bool {
        guard !loadBlocked else { return false }
        return commit(entries.filter { $0.id != id })
    }
    @discardableResult func clear() -> Bool {
        let saved = commit([])
        if saved { loadBlocked = false }
        return saved
    }
    private func commit(_ candidate: [ShazamHistoryEntry]) -> Bool {
        do {
            let data = try JSONEncoder().encode(Document(version: 1, entries: candidate))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            entries = candidate; persistenceError = nil
            return true
        } catch {
            persistenceError = "Changes to Shazam History could not be saved. Your existing history has not been changed. Try again when storage is available."
            return false
        }
    }
}
