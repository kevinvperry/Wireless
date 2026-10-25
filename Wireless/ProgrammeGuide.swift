import Foundation
import Combine

struct Programme: Decodable, Identifiable {
    let id: String
    let name: String
    let start: Date
    let end: Date
    let presenter: String?

    init(id: String, name: String, start: Date, end: Date, presenter: String? = nil) {
        self.id = id; self.name = name; self.start = start; self.end = end; self.presenter = presenter
    }

    private enum CodingKeys: String, CodingKey { case id, name, start, end, presenter }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        start = try values.decode(Date.self, forKey: .start)
        end = try values.decode(Date.self, forKey: .end)
        presenter = try values.decodeIfPresent(String.self, forKey: .presenter)
    }

    var timeLabel: String {
        "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct SENProgrammeResponse: Decodable {
    let nowPlaying: Programme?
    let nowPlayingList: [Programme]
}

private struct TaptScheduleEntry: Decodable {
    let id: String
    let showName: String
    let startDay: String
    let startTime: String
    let endDay: String
    let endTime: String
    let presenter: String

    enum CodingKeys: String, CodingKey {
        case id
        case showName = "show_name"
        case startDay = "start_day"
        case startTime = "start_time"
        case endDay = "end_day"
        case endTime = "end_time"
        case presenter = "substitute_presenter"
    }
}

private enum ProgrammeSource: Equatable {
    case abc(serviceID: String)
    case sen(channelID: String)
    case tapt(website: URL, timeZoneIdentifier: String)
}

@MainActor
final class ProgrammeGuide: ObservableObject {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let loader: Loader
    private let now: @Sendable () -> Date

    init(loader: @escaping Loader = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.loader = loader
        self.now = now
    }

    @Published private(set) var current: Programme?
    @Published private(set) var upcoming: [Programme] = []
    @Published private(set) var message = ""

    private var source: ProgrammeSource?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var taptSchedule: [TaptScheduleEntry] = []
    private var taptFetchedAt: Date?
    private var abcCache: (serviceID: String, day: String, fetchedAt: Date, programmes: [Programme])?

    func startABC(serviceID: String) { start(source: .abc(serviceID: serviceID)) }

    func start(channelID: String) { start(source: .sen(channelID: channelID)) }

    func startTapt(website: URL, timeZoneIdentifier: String) {
        start(source: .tapt(website: website, timeZoneIdentifier: timeZoneIdentifier))
    }

    private func start(source newSource: ProgrammeSource) {
        if source != newSource {
            refreshTask?.cancel()
            current = nil; upcoming = []; message = "Loading programme guide…"
            taptSchedule = []; taptFetchedAt = nil; abcCache = nil; source = newSource
        }
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        refreshTask?.cancel(); refreshTask = nil
        source = nil; taptSchedule = []; taptFetchedAt = nil; abcCache = nil
        current = nil; upcoming = []; message = ""
    }

    func refresh() {
        guard let source else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let programmes: [Programme]
                switch source {
                case .abc(let serviceID): programmes = try await fetchABC(serviceID: serviceID)
                case .sen(let channelID): programmes = try await fetchSEN(channelID: channelID)
                case .tapt(let website, let timeZoneIdentifier):
                    programmes = try await fetchTapt(website: website, timeZoneIdentifier: timeZoneIdentifier)
                }
                try Task.checkCancellation()
                guard self.source == source else { return }
                apply(programmes, now: now())
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, self.source == source else { return }
                if let current, current.end <= now() { self.current = nil }
                upcoming.removeAll { $0.start < now() }
                message = current == nil ? "Programme guide unavailable" : "Programme guide could not refresh"
            }
        }
    }

    private func fetchABC(serviceID: String) async throws -> [Programme] {
        let now = now()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now)
        if let cache = abcCache, cache.serviceID == serviceID, cache.day == day,
           now.timeIntervalSince(cache.fetchedAt) < 5 * 60 {
            return cache.programmes
        }
        // Include both sides of midnight: a programme may have begun yesterday,
        // and tomorrow's first programme should still appear in Coming up.
        var programmes: [Programme] = []
        for offset in -1...1 {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            var components = URLComponents(string: "https://www.abc.net.au/core-next/api/schedule")!
            components.queryItems = [
                URLQueryItem(name: "service", value: serviceID),
                URLQueryItem(name: "date", value: formatter.string(from: date)),
                URLQueryItem(name: "tz", value: "UTC"),
                URLQueryItem(name: "ratio", value: "1x1")
            ]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await loader(request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            programmes += try ABCProgrammeParser.parse(data, serviceID: serviceID)
        }
        // ABC's RN_VIC and RN_TAS schedule services currently return no entries.
        // Use the national eastern schedule only for these two eastern-time feeds;
        // delayed QLD/SA/NT/WA services must retain their own schedules.
        if programmes.isEmpty, ["RN_VIC", "RN_TAS"].contains(serviceID) {
            programmes = try await fetchABC(serviceID: "RN")
        }
        var ids = Set<String>()
        programmes = programmes.filter { ids.insert($0.id).inserted }
        abcCache = (serviceID, day, now, programmes)
        return programmes
    }

    private func fetchSEN(channelID: String) async throws -> [Programme] {
        var components = URLComponents(string: "https://www.sen.com.au/api/radioplayer")!
        components.queryItems = [URLQueryItem(name: "channelID", value: channelID)]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 12
        let (data, response) = try await loader(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let guide = try decoder.decode(SENProgrammeResponse.self, from: data)
        var programmes = guide.nowPlayingList
        if let current = guide.nowPlaying, !programmes.contains(where: { $0.id == current.id }) { programmes.append(current) }
        return programmes
    }

    private func fetchTapt(website: URL, timeZoneIdentifier: String) async throws -> [Programme] {
        if let taptFetchedAt, now().timeIntervalSince(taptFetchedAt) < 15 * 60, !taptSchedule.isEmpty {
            return Self.programmes(from: taptSchedule, timeZoneIdentifier: timeZoneIdentifier, now: now())
        }
        var request = URLRequest(url: website)
        request.cachePolicy = .reloadRevalidatingCacheData; request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; Wireless Radio)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await loader(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let schedule = try Self.decodeTaptSchedule(from: html)
        taptSchedule = schedule; taptFetchedAt = now()
        return Self.programmes(from: schedule, timeZoneIdentifier: timeZoneIdentifier, now: now())
    }

    private func apply(_ programmes: [Programme], now: Date) {
        let ordered = programmes.sorted { $0.start < $1.start }
        current = ordered.last { $0.start <= now && now < $0.end }
        upcoming = ordered.filter { $0.start >= now && $0.id != current?.id }
        message = current == nil ? "No current programme listed" : ""
    }

    private static func decodeTaptSchedule(from html: String) throws -> [TaptScheduleEntry] {
        let marker = "var player_data = "
        guard let markerRange = html.range(of: marker) else { throw URLError(.cannotParseResponse) }
        let remainder = html[markerRange.upperBound...]
        guard let start = remainder.firstIndex(of: "{") else { throw URLError(.cannotParseResponse) }
        var depth = 0, inString = false, escaped = false
        var end: String.Index?
        for index in remainder.indices[start...] {
            let character = remainder[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0 { end = remainder.index(after: index); break }
            }
        }
        guard let end,
              let objectData = String(remainder[start..<end]).data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: objectData) as? [String: Any],
              let encodedSchedule = object["schedule"] as? String,
              let scheduleData = encodedSchedule.data(using: .utf8) else { throw URLError(.cannotParseResponse) }
        return try JSONDecoder().decode([TaptScheduleEntry].self, from: scheduleData)
    }

    private static func programmes(from schedule: [TaptScheduleEntry], timeZoneIdentifier: String, now: Date) -> [Programme] {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return [] }
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = timeZone
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let offsets = ["Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3, "Friday": 4, "Saturday": 5, "Sunday": 6]
        func clock(_ value: String) -> (Int, Int)? {
            let values = value.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return values.count == 2 ? (values[0], values[1]) : nil
        }
        func date(day: String, time: String, week: Int) -> Date? {
            guard let offset = offsets[day], let (hour, minute) = clock(time),
                  let dayDate = calendar.date(byAdding: .day, value: offset + week * 7, to: weekStart) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate)
        }
        return (-1...1).flatMap { week in schedule.compactMap { entry in
            guard let start = date(day: entry.startDay, time: entry.startTime, week: week),
                  var end = date(day: entry.endDay, time: entry.endTime, week: week) else { return nil }
            if end <= start { end = calendar.date(byAdding: .day, value: 7, to: end) ?? end }
            let presenter = entry.presenter.trimmingCharacters(in: .whitespacesAndNewlines)
            return Programme(id: "tapt-\(entry.id)-\(Int(start.timeIntervalSince1970))", name: entry.showName,
                             start: start, end: end, presenter: presenter.isEmpty ? nil : presenter)
        } }
    }
}

/// The same schedule payload used by ABC listen's website. Absolute timestamps,
/// rather than the formatted clock labels or onNow flag, determine live programmes.
enum ABCProgrammeParser {
    private struct Response: Decodable { let formattedScheduleArray: [Block] }
    private struct Block: Decodable { let items: [Item]? }
    private struct Item: Decodable {
        let id: String?
        let title: String?
        let rawStartTime: String?
        let rawEndTime: String?
        let presenters: [Presenter]?
    }
    private struct Presenter: Decodable { let displayName: String? }

    static func parse(_ data: Data, serviceID: String) throws -> [Programme] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: String?) -> Date? {
            guard let value else { return nil }
            return iso.date(from: value) ?? fractional.date(from: value)
        }
        return response.formattedScheduleArray.flatMap { $0.items ?? [] }.compactMap { item in
            guard let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = date(item.rawStartTime), let end = date(item.rawEndTime), end > start else { return nil }
            let presenters = (item.presenters ?? []).compactMap { $0.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: ", ")
            return Programme(id: "abc-\(serviceID)-\(item.id ?? "programme")-\(Int(start.timeIntervalSince1970))",
                             name: title, start: start, end: end, presenter: presenters.isEmpty ? nil : presenters)
        }
    }
}
