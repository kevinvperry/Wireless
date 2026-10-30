import Foundation

/// Display-only projection, adapted from Autohop. No stream URLs or credentials.
struct WidgetDisplayStation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let thumbnailFilename: String?
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let generatedAt: Date
    let current: WidgetDisplayStation?
    let favourites: [WidgetDisplayStation]
    let isPlaying: Bool

    var primary: WidgetDisplayStation? { current ?? favourites.first }
    var following: [WidgetDisplayStation] {
        favourites.filter { $0.id != primary?.id }
    }
}
