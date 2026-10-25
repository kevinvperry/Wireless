import Foundation

enum WirelessListeningMode: String, Codable, CaseIterable, Sendable {
    case live
    case tvSync
    case vocalBoost
    case deepBass
    case midBass

    var title: String {
        switch self {
        case .live: "Live"
        case .tvSync: "TV Sync"
        case .vocalBoost: "Vocal Boost"
        case .deepBass: "Deep Bass"
        case .midBass: "Mid Bass"
        }
    }
}

enum WirelessAudioRouteCategory: String, Codable, CaseIterable, Sendable {
    case thisDevice
    case headphones
    case bluetooth
    case airPlay
    case carPlay
    case other

    var title: String {
        switch self {
        case .thisDevice: "This Device"
        case .headphones: "Headphones"
        case .bluetooth: "Bluetooth"
        case .airPlay: "AirPlay"
        case .carPlay: "CarPlay"
        case .other: "Other"
        }
    }
}

struct WirelessStationStatsSnapshot: Codable, Equatable, Sendable {
    let id: String
    var name: String
    var network: String
    var location: String
    var artworkURL: String
}

enum WirelessListeningSessionEndReason: String, Codable, Sendable {
    case paused
    case stationChanged
    case playbackEnded
}

struct WirelessListeningSession: Codable, Equatable, Sendable {
    static let historyMinimumSeconds: TimeInterval = 60

    let id: String
    let stationID: String
    let startedAt: Date
    var endedAt: Date
    var renderedSeconds: TimeInterval
    var endReason: WirelessListeningSessionEndReason? = nil

    var isHistoryEligible: Bool {
        renderedSeconds >= Self.historyMinimumSeconds
    }
}

struct WirelessListeningHistoryItem: Identifiable, Equatable, Sendable {
    let session: WirelessListeningSession
    let station: WirelessStationStatsSnapshot

    var id: String { session.id }
}

struct WirelessListeningHistorySummary: Equatable, Sendable {
    var items: [WirelessListeningHistoryItem]

    var listeningSeconds: TimeInterval {
        items.reduce(0) { $0 + $1.session.renderedSeconds }
    }

    var sessionCount: Int { items.count }
}

struct WirelessDayStats: Codable, Equatable, Sendable {
    var dayKey: String
    var listeningSeconds: TimeInterval
    var hourSeconds: [TimeInterval]
    var perStationSeconds: [String: TimeInterval]
    var stationSnapshots: [String: WirelessStationStatsSnapshot]
    var sessions: [String: WirelessListeningSession]
    var modeSeconds: [String: TimeInterval]
    var routeSeconds: [String: TimeInterval]

    init(
        dayKey: String,
        listeningSeconds: TimeInterval = 0,
        hourSeconds: [TimeInterval] = Array(repeating: 0, count: 24),
        perStationSeconds: [String: TimeInterval] = [:],
        stationSnapshots: [String: WirelessStationStatsSnapshot] = [:],
        sessions: [String: WirelessListeningSession] = [:],
        modeSeconds: [String: TimeInterval] = [:],
        routeSeconds: [String: TimeInterval] = [:]
    ) {
        self.dayKey = dayKey
        self.listeningSeconds = listeningSeconds
        self.hourSeconds = hourSeconds
        self.perStationSeconds = perStationSeconds
        self.stationSnapshots = stationSnapshots
        self.sessions = sessions
        self.modeSeconds = modeSeconds
        self.routeSeconds = routeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case dayKey, listeningSeconds, hourSeconds, perStationSeconds
        case stationSnapshots, sessions, modeSeconds, routeSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try values.decode(String.self, forKey: .dayKey)
        listeningSeconds = try values.decode(TimeInterval.self, forKey: .listeningSeconds)
        let decodedHours = try values.decodeIfPresent([TimeInterval].self, forKey: .hourSeconds) ?? []
        hourSeconds = Array(decodedHours.prefix(24))
        if hourSeconds.count < 24 {
            hourSeconds.append(contentsOf: repeatElement(0, count: 24 - hourSeconds.count))
        }
        perStationSeconds = try values.decodeIfPresent([String: TimeInterval].self, forKey: .perStationSeconds) ?? [:]
        stationSnapshots = try values.decodeIfPresent([String: WirelessStationStatsSnapshot].self, forKey: .stationSnapshots) ?? [:]
        sessions = try values.decodeIfPresent([String: WirelessListeningSession].self, forKey: .sessions) ?? [:]
        modeSeconds = try values.decodeIfPresent([String: TimeInterval].self, forKey: .modeSeconds) ?? [:]
        routeSeconds = try values.decodeIfPresent([String: TimeInterval].self, forKey: .routeSeconds) ?? [:]
    }

    var isValid: Bool {
        !dayKey.isEmpty
            && listeningSeconds.isFinite && listeningSeconds >= 0
            && hourSeconds.count == 24
            && hourSeconds.allSatisfy { $0.isFinite && $0 >= 0 }
            && perStationSeconds.values.allSatisfy { $0.isFinite && $0 >= 0 }
            && modeSeconds.values.allSatisfy { $0.isFinite && $0 >= 0 }
            && routeSeconds.values.allSatisfy { $0.isFinite && $0 >= 0 }
            && sessions.values.allSatisfy { $0.renderedSeconds.isFinite && $0.renderedSeconds >= 0 }
    }
}

enum WirelessStatsPeriod: Hashable {
    case currentWeek
    case previousWeek
    case currentMonth
    case previousMonth
    case currentYear
    case previousYear
    case lifetime
}

struct WirelessListeningStatsSummary {
    var listeningSeconds: TimeInterval = 0
    var hourSeconds = Array(repeating: TimeInterval(0), count: 24)
    var perStationSeconds: [String: TimeInterval] = [:]
    var stationSnapshots: [String: WirelessStationStatsSnapshot] = [:]
    var sessions: [String: WirelessListeningSession] = [:]
    var modeSeconds: [String: TimeInterval] = [:]
    var routeSeconds: [String: TimeInterval] = [:]
    var days: [WirelessDayStats] = []

    var stationCount: Int { perStationSeconds.values.filter { $0 > 0 }.count }
    var sessionCount: Int { sessions.count }
    var averageSessionSeconds: TimeInterval {
        guard sessionCount > 0 else { return 0 }
        return sessions.values.reduce(0) { $0 + $1.renderedSeconds } / Double(sessionCount)
    }
    var longestSessionSeconds: TimeInterval {
        sessions.values.map(\.renderedSeconds).max() ?? 0
    }

    func topStations(limit: Int) -> [(snapshot: WirelessStationStatsSnapshot, seconds: TimeInterval)] {
        perStationSeconds
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (stationSnapshots[lhs.key]?.name ?? lhs.key)
                    .localizedStandardCompare(stationSnapshots[rhs.key]?.name ?? rhs.key) == .orderedAscending
            }
            .prefix(limit)
            .map { key, seconds in
                let snapshot = stationSnapshots[key]
                    ?? WirelessStationStatsSnapshot(id: key, name: "Unknown Station", network: "", location: "", artworkURL: "")
                return (snapshot, seconds)
            }
    }
}
