import Foundation

/// Adapted from Autohop's widget storage. Atomic snapshots and prepared artwork
/// are shared through the signed App Group, available after first unlock.
/// The extension never opens the app's catalogue or playback services.
enum WidgetSharedConfiguration {
    static let appGroupIdentifier = "group.au.com.kevmarl.Wireless"
    static let widgetKind = "WirelessStationsWidget"
    static let snapshotFilename = "widget-snapshot.json"
    static let artworkDirectoryName = "WidgetArtwork"
    static let maximumThumbnailBytes = 1 * 1_024 * 1_024
}

enum WidgetSharedStorageError: Error, Equatable {
    case appGroupContainerUnavailable
    case invalidThumbnailFilename
    case unsupportedSchemaVersion(Int)
}

struct WidgetSharedStorage {
    private let fileManager: FileManager
    private let containerURL: URL?

    init(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = WidgetSharedConfiguration.appGroupIdentifier
    ) {
        self.fileManager = fileManager
        self.containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// Test seam and future preview support; production code uses the App Group
    /// initializer above.
    init(containerURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.containerURL = containerURL
    }

    func prepareDirectories() throws {
        let container = try resolvedContainerURL()
        try fileManager.createDirectory(
            at: container,
            withIntermediateDirectories: true
        )
        let artworkDirectory = container.appendingPathComponent(
            WidgetSharedConfiguration.artworkDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: artworkDirectory,
            withIntermediateDirectories: true
        )
        try applyAfterFirstUnlockProtection(to: artworkDirectory)
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else {
            throw WidgetSharedStorageError.unsupportedSchemaVersion(
                snapshot.schemaVersion
            )
        }
        try prepareDirectories()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        let destination = try snapshotURL()
        try data.write(to: destination, options: .atomic)
        try applyAfterFirstUnlockProtection(to: destination)
    }

    func read() throws -> WidgetSnapshot? {
        let location = try snapshotURL()
        guard fileManager.fileExists(atPath: location.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(
            WidgetSnapshot.self,
            from: Data(contentsOf: location)
        )
        guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else {
            throw WidgetSharedStorageError.unsupportedSchemaVersion(
                snapshot.schemaVersion
            )
        }
        return snapshot
    }

    /// Recovery seam for an invalid/truncated snapshot. The extension removes
    /// only this display projection—never artwork or application data—so a bad
    /// file cannot trap every future timeline in repeated decode failures. The
    /// app's next meaningful event republishes a complete atomic replacement.
    func removeSnapshot() throws {
        let location = try snapshotURL()
        guard fileManager.fileExists(atPath: location.path) else { return }
        try fileManager.removeItem(at: location)
    }

    func snapshotURL() throws -> URL {
        try resolvedContainerURL().appendingPathComponent(
            WidgetSharedConfiguration.snapshotFilename,
            isDirectory: false
        )
    }

    func artworkDirectoryURL() throws -> URL {
        try resolvedContainerURL().appendingPathComponent(
            WidgetSharedConfiguration.artworkDirectoryName,
            isDirectory: true
        )
    }

    func thumbnailURL(filename: String) throws -> URL {
        guard !filename.isEmpty,
              filename == (filename as NSString).lastPathComponent,
              filename != ".",
              filename != ".."
        else {
            throw WidgetSharedStorageError.invalidThumbnailFilename
        }
        return try artworkDirectoryURL().appendingPathComponent(
            filename,
            isDirectory: false
        )
    }

    func writeThumbnail(_ data: Data, filename: String) throws {
        try prepareDirectories()
        let destination = try thumbnailURL(filename: filename)
        try data.write(to: destination, options: .atomic)
        try applyAfterFirstUnlockProtection(to: destination)
    }

    func thumbnailFilenames() throws -> Set<String> {
        let directory = try artworkDirectoryURL()
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return Set(
            try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { !$0.hasDirectoryPath }
            .map(\.lastPathComponent)
        )
    }

    func removeThumbnails(except retainedFilenames: Set<String>) throws {
        for filename in try thumbnailFilenames()
        where !retainedFilenames.contains(filename) {
            try fileManager.removeItem(at: try thumbnailURL(filename: filename))
        }
    }

    private func resolvedContainerURL() throws -> URL {
        guard let containerURL else {
            throw WidgetSharedStorageError.appGroupContainerUnavailable
        }
        return containerURL
    }

    private func applyAfterFirstUnlockProtection(to url: URL) throws {
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
