import Combine
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class WirelessListeningStatsStore: ObservableObject {
    static let shared = WirelessListeningStatsStore()
    static let detailedSessionLimit = 5_000

    enum LoadState: Equatable {
        case absent
        case loaded
        case recoveredBackup
        case unavailable
        case failed

        var permitsSaving: Bool {
            switch self {
            case .absent, .loaded, .recoveredBackup: true
            case .unavailable, .failed: false
            }
        }
    }

    struct HealthSnapshot {
        let recordedDays: Int
        let trackingStarted: Date
        let lastLocalSave: Date?
        let status: String
    }

    private struct StatsData: Codable, Equatable {
        var startedAt = Date()
        var days: [String: WirelessDayStats] = [:]

        var isValid: Bool {
            startedAt.timeIntervalSinceReferenceDate.isFinite
                && days.allSatisfy { $0.key == $0.value.dayKey && $0.value.isValid }
        }
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let generationID: String
        let revision: UInt64
        let checksum: String
        let payload: Data
    }

    private struct ActiveSession {
        let id: String
        let stationID: String
        let startedAt: Date
        let startDayKey: String
        var renderedSeconds: TimeInterval
    }

    @Published private(set) var revision = 0
    @Published private(set) var loadState: LoadState = .absent

    private var data = StatsData()
    private var activeSession: ActiveSession?
    private var storageRevision: UInt64 = 0
    private var generationID = UUID().uuidString
    private var lastSaveDate: Date?
    private var lastAutomaticSave = Date.distantPast
    private let automaticSaveInterval: TimeInterval = 30
    private let fileURL: URL?
    private let backupURL: URL?
    private let calendarProvider: () -> Calendar
    private let protectedDataAvailable: () -> Bool
    private var protectedDataObserver: NSObjectProtocol?

    init(
        fileURL: URL? = nil,
        calendarProvider: @escaping () -> Calendar = { .current },
        protectedDataAvailable: (() -> Bool)? = nil
    ) {
        let resolved = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Wireless", isDirectory: true)
            .appendingPathComponent("listening-stats.json")
        self.fileURL = resolved
        self.backupURL = resolved?.deletingLastPathComponent().appendingPathComponent("listening-stats.backup.json")
        self.calendarProvider = calendarProvider
        #if canImport(UIKit)
        self.protectedDataAvailable = protectedDataAvailable ?? { UIApplication.shared.isProtectedDataAvailable }
        #else
        self.protectedDataAvailable = protectedDataAvailable ?? { true }
        #endif
        load()
        #if canImport(UIKit)
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.retryUnavailableLoad() }
        }
        #endif
    }

    func recordRendered(
        seconds: TimeInterval,
        station: DirectoryStation,
        mode: WirelessListeningMode,
        route: WirelessAudioRouteCategory,
        endedAt: Date = Date()
    ) {
        guard loadState.permitsSaving,
              station.id != DirectoryStation.unselected.id,
              seconds.isFinite, seconds > 0 else { return }

        let startsNewSession = activeSession?.stationID != station.id
        if startsNewSession {
            endSession(reason: .stationChanged)
            let start = endedAt.addingTimeInterval(-seconds)
            activeSession = ActiveSession(
                id: UUID().uuidString,
                stationID: station.id,
                startedAt: start,
                startDayKey: dayKey(for: start),
                renderedSeconds: 0
            )
        }

        let snapshot = WirelessStationStatsSnapshot(
            id: station.id,
            name: station.name,
            network: station.network,
            location: station.location,
            artworkURL: station.logo_url
        )
        let segments = split(seconds: seconds, endedAt: endedAt)
        for segment in segments {
            var day = data.days[segment.dayKey] ?? WirelessDayStats(dayKey: segment.dayKey)
            day.listeningSeconds += segment.seconds
            day.hourSeconds[segment.hour] += segment.seconds
            day.perStationSeconds[station.id, default: 0] += segment.seconds
            day.stationSnapshots[station.id] = snapshot
            day.modeSeconds[mode.rawValue, default: 0] += segment.seconds
            day.routeSeconds[route.rawValue, default: 0] += segment.seconds
            data.days[segment.dayKey] = day
        }

        if var session = activeSession {
            session.renderedSeconds += seconds
            activeSession = session
            var startDay = data.days[session.startDayKey] ?? WirelessDayStats(dayKey: session.startDayKey)
            startDay.stationSnapshots[station.id] = snapshot
            startDay.sessions[session.id] = WirelessListeningSession(
                id: session.id,
                stationID: station.id,
                startedAt: session.startedAt,
                endedAt: endedAt,
                renderedSeconds: session.renderedSeconds
            )
            data.days[session.startDayKey] = startDay
            if startsNewSession { pruneDetailedSessionsIfNeeded() }
        }

        storageRevision &+= 1
        revision &+= 1
        if Date().timeIntervalSince(lastAutomaticSave) >= automaticSaveInterval {
            save()
        }
    }

    func endSession(reason: WirelessListeningSessionEndReason = .paused) {
        if let activeSession,
           var day = data.days[activeSession.startDayKey],
           var session = day.sessions[activeSession.id] {
            session.endReason = reason
            day.sessions[activeSession.id] = session
            data.days[activeSession.startDayKey] = day
            storageRevision &+= 1
            revision &+= 1
        }
        activeSession = nil
    }

    var activeSessionID: String? { activeSession?.id }

    func listeningHistory() -> WirelessListeningHistorySummary {
        let snapshots = data.days.values.reduce(into: [String: WirelessStationStatsSnapshot]()) { result, day in
            result.merge(day.stationSnapshots) { _, latest in latest }
        }
        let items = data.days.values
            .flatMap { $0.sessions.values }
            .filter(\.isHistoryEligible)
            .sorted {
                if $0.endedAt != $1.endedAt { return $0.endedAt > $1.endedAt }
                return $0.startedAt > $1.startedAt
            }
            .map { session in
                WirelessListeningHistoryItem(
                    session: session,
                    station: snapshots[session.stationID]
                        ?? WirelessStationStatsSnapshot(
                            id: session.stationID,
                            name: "Unknown Station",
                            network: "",
                            location: "",
                            artworkURL: ""
                        )
                )
            }
        return WirelessListeningHistorySummary(items: items)
    }

    func checkpoint() {
        save()
    }

    func summary(for period: WirelessStatsPeriod, now: Date = Date()) -> WirelessListeningStatsSummary {
        let bounds = dateBounds(for: period, now: now)
        let selected = data.days.values
            .filter { day in
                guard let date = date(for: day.dayKey) else { return false }
                if let lower = bounds.lower, date < lower { return false }
                if let upper = bounds.upper, date >= upper { return false }
                return true
            }
            .sorted { $0.dayKey < $1.dayKey }

        var result = WirelessListeningStatsSummary(days: zeroFilledDays(from: selected, bounds: bounds, now: now))
        for day in selected {
            result.listeningSeconds += day.listeningSeconds
            for hour in 0..<24 { result.hourSeconds[hour] += day.hourSeconds[hour] }
            for (key, value) in day.perStationSeconds { result.perStationSeconds[key, default: 0] += value }
            result.stationSnapshots.merge(day.stationSnapshots) { _, latest in latest }
            result.sessions.merge(day.sessions) { existing, incoming in
                incoming.endedAt > existing.endedAt ? incoming : existing
            }
            for (key, value) in day.modeSeconds { result.modeSeconds[key, default: 0] += value }
            for (key, value) in day.routeSeconds { result.routeSeconds[key, default: 0] += value }
        }
        return result
    }

    func previousPeriodStationSeconds(for period: WirelessStatsPeriod, now: Date = Date()) -> [String: TimeInterval]? {
        let previous: WirelessStatsPeriod
        switch period {
        case .currentWeek: previous = .previousWeek
        case .currentMonth: previous = .previousMonth
        case .currentYear: previous = .previousYear
        case .previousWeek:
            return stationSeconds(from: startOfWeek(now).addingTimeInterval(-14 * 86_400), to: startOfWeek(now).addingTimeInterval(-7 * 86_400))
        case .previousMonth:
            let current = startOfMonth(now)
            guard let start = calendarProvider().date(byAdding: .month, value: -2, to: current),
                  let end = calendarProvider().date(byAdding: .month, value: -1, to: current) else { return [:] }
            return stationSeconds(from: start, to: end)
        case .previousYear:
            let current = startOfYear(now)
            guard let start = calendarProvider().date(byAdding: .year, value: -2, to: current),
                  let end = calendarProvider().date(byAdding: .year, value: -1, to: current) else { return [:] }
            return stationSeconds(from: start, to: end)
        case .lifetime: return nil
        }
        return summary(for: previous, now: now).perStationSeconds
    }

    var currentStreakDays: Int {
        let calendar = calendarProvider()
        var cursor = calendar.startOfDay(for: Date())
        if (data.days[dayKey(for: cursor)]?.listeningSeconds ?? 0) < 60 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while (data.days[dayKey(for: cursor)]?.listeningSeconds ?? 0) >= 60 {
            streak += 1
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return streak
    }

    var healthSnapshot: HealthSnapshot {
        let status: String
        switch loadState {
        case .absent, .loaded: status = "Healthy"
        case .recoveredBackup: status = "Recovered from backup"
        case .unavailable: status = "Waiting for protected data"
        case .failed: status = "Needs attention"
        }
        return HealthSnapshot(
            recordedDays: data.days.values.filter { $0.listeningSeconds > 0 }.count,
            trackingStarted: data.startedAt,
            lastLocalSave: lastSaveDate,
            status: status
        )
    }

    func makeJSONExport() throws -> URL {
        let encoder = configuredEncoder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wireless-Listening-Stats.json")
        try encoder.encode(data).write(to: url, options: .atomic)
        return url
    }

    func makeCSVExport() throws -> URL {
        var lines = ["date,station_id,station_name,seconds,hours"]
        for day in data.days.values.sorted(by: { $0.dayKey < $1.dayKey }) {
            for (stationID, seconds) in day.perStationSeconds.sorted(by: { $0.key < $1.key }) {
                let name = csv(day.stationSnapshots[stationID]?.name ?? "Unknown Station")
                lines.append("\(day.dayKey),\(csv(stationID)),\(name),\(Int(seconds.rounded())),\(String(format: "%.4f", seconds / 3600))")
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wireless-Listening-Stats.csv")
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    func importJSON(from url: URL) throws {
        let incoming = try configuredDecoder().decode(StatsData.self, from: Data(contentsOf: url))
        guard incoming.isValid else { throw CocoaError(.fileReadCorruptFile) }
        for (key, value) in incoming.days {
            if let existing = data.days[key] {
                data.days[key] = merged(existing, value)
            } else {
                data.days[key] = value
            }
        }
        data.startedAt = min(data.startedAt, incoming.startedAt)
        pruneDetailedSessionsIfNeeded()
        storageRevision &+= 1
        revision &+= 1
        save()
    }

    func save() {
        guard loadState.permitsSaving, let fileURL, protectedDataAvailable() else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try encodeEnvelope()
            if FileManager.default.fileExists(atPath: fileURL.path),
               (try? validatedData(at: fileURL)) != nil,
               let backupURL {
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.copyItem(at: fileURL, to: backupURL)
                protect(backupURL)
            }
            try encoded.write(to: fileURL, options: .atomic)
            protect(fileURL)
            lastSaveDate = Date()
            lastAutomaticSave = lastSaveDate ?? Date()
            if loadState == .absent { loadState = .loaded }
        } catch {
            loadState = .failed
        }
    }

    private func load() {
        guard protectedDataAvailable() else { loadState = .unavailable; return }
        guard let fileURL else { loadState = .failed; return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            if let backupURL, FileManager.default.fileExists(atPath: backupURL.path),
               let recovered = try? validatedData(at: backupURL) {
                data = recovered
                loadState = .recoveredBackup
                save()
            } else {
                loadState = .absent
            }
            return
        }
        do {
            data = try validatedData(at: fileURL)
            pruneDetailedSessionsIfNeeded()
            loadState = .loaded
        } catch {
            quarantine(fileURL)
            if let backupURL, let recovered = try? validatedData(at: backupURL) {
                data = recovered
                loadState = .recoveredBackup
                save()
            } else {
                loadState = .failed
            }
        }
    }

    private func retryUnavailableLoad() {
        guard loadState == .unavailable else { return }
        let pending = data
        load()
        guard loadState.permitsSaving else { return }
        for (key, value) in pending.days {
            data.days[key] = data.days[key].map { merged($0, value) } ?? value
        }
        data.startedAt = min(data.startedAt, pending.startedAt)
        save()
    }

    private func encodeEnvelope() throws -> Data {
        let payload = try configuredEncoder().encode(data)
        let checksum = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return try configuredEncoder().encode(Envelope(
            schemaVersion: 1,
            generationID: generationID,
            revision: storageRevision,
            checksum: checksum,
            payload: payload
        ))
    }

    private func validatedData(at url: URL) throws -> StatsData {
        let envelope = try configuredDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        let checksum = SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
        guard checksum == envelope.checksum else { throw CocoaError(.fileReadCorruptFile) }
        let decoded = try configuredDecoder().decode(StatsData.self, from: envelope.payload)
        guard decoded.isValid else { throw CocoaError(.fileReadCorruptFile) }
        generationID = envelope.generationID
        storageRevision = envelope.revision
        return decoded
    }

    private func merged(_ lhs: WirelessDayStats, _ rhs: WirelessDayStats) -> WirelessDayStats {
        var result = lhs
        result.listeningSeconds = max(lhs.listeningSeconds, rhs.listeningSeconds)
        for hour in 0..<24 { result.hourSeconds[hour] = max(lhs.hourSeconds[hour], rhs.hourSeconds[hour]) }
        for (key, value) in rhs.perStationSeconds { result.perStationSeconds[key] = max(result.perStationSeconds[key] ?? 0, value) }
        result.stationSnapshots.merge(rhs.stationSnapshots) { _, incoming in incoming }
        result.sessions.merge(rhs.sessions) { existing, incoming in
            incoming.renderedSeconds > existing.renderedSeconds ? incoming : existing
        }
        for (key, value) in rhs.modeSeconds { result.modeSeconds[key] = max(result.modeSeconds[key] ?? 0, value) }
        for (key, value) in rhs.routeSeconds { result.routeSeconds[key] = max(result.routeSeconds[key] ?? 0, value) }
        return result
    }

    private func pruneDetailedSessionsIfNeeded() {
        let sessions = data.days.values.flatMap { day in
            day.sessions.values.map { (day.dayKey, $0) }
        }
        guard sessions.count > Self.detailedSessionLimit else { return }
        let excess = sessions.count - Self.detailedSessionLimit
        let oldest = sessions.sorted {
            if $0.1.endedAt != $1.1.endedAt { return $0.1.endedAt < $1.1.endedAt }
            return $0.1.startedAt < $1.1.startedAt
        }.prefix(excess)
        for (dayKey, session) in oldest {
            data.days[dayKey]?.sessions.removeValue(forKey: session.id)
        }
    }

    private struct Segment { let dayKey: String; let hour: Int; let seconds: TimeInterval }

    private func split(seconds: TimeInterval, endedAt: Date) -> [Segment] {
        let calendar = calendarProvider()
        var cursor = endedAt.addingTimeInterval(-seconds)
        var remaining = seconds
        var result: [Segment] = []
        while remaining > 0.000_1 {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? endedAt
            let portion = min(remaining, max(0.000_1, nextHour.timeIntervalSince(cursor)))
            result.append(Segment(dayKey: dayKey(for: cursor), hour: hour, seconds: portion))
            cursor = cursor.addingTimeInterval(portion)
            remaining -= portion
        }
        return result
    }

    private func dateBounds(for period: WirelessStatsPeriod, now: Date) -> (lower: Date?, upper: Date?) {
        let calendar = calendarProvider()
        switch period {
        case .currentWeek: return (startOfWeek(now), nil)
        case .previousWeek:
            let end = startOfWeek(now)
            return (calendar.date(byAdding: .day, value: -7, to: end), end)
        case .currentMonth: return (startOfMonth(now), nil)
        case .previousMonth:
            let end = startOfMonth(now)
            return (calendar.date(byAdding: .month, value: -1, to: end), end)
        case .currentYear: return (startOfYear(now), nil)
        case .previousYear:
            let end = startOfYear(now)
            return (calendar.date(byAdding: .year, value: -1, to: end), end)
        case .lifetime: return (nil, nil)
        }
    }

    private func zeroFilledDays(
        from selected: [WirelessDayStats],
        bounds: (lower: Date?, upper: Date?),
        now: Date
    ) -> [WirelessDayStats] {
        guard let lower = bounds.lower else { return selected }
        let calendar = calendarProvider()
        let upper = min(bounds.upper ?? now.addingTimeInterval(1), now.addingTimeInterval(1))
        let lookup = Dictionary(uniqueKeysWithValues: selected.map { ($0.dayKey, $0) })
        var result: [WirelessDayStats] = []
        var cursor = calendar.startOfDay(for: lower)
        while cursor < upper {
            let key = dayKey(for: cursor)
            result.append(lookup[key] ?? WirelessDayStats(dayKey: key))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func stationSeconds(from start: Date, to end: Date) -> [String: TimeInterval] {
        data.days.values.reduce(into: [:]) { totals, day in
            guard let date = date(for: day.dayKey), date >= start, date < end else { return }
            for (key, value) in day.perStationSeconds { totals[key, default: 0] += value }
        }
    }

    private func startOfWeek(_ date: Date) -> Date {
        let calendar = calendarProvider()
        let start = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: start) - 2 + 7) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = calendarProvider()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func startOfYear(_ date: Date) -> Date {
        let calendar = calendarProvider()
        return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendarProvider().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func date(for key: String) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendarProvider().date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }

    private func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func quarantine(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = url.deletingLastPathComponent().appendingPathComponent("listening-stats.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
