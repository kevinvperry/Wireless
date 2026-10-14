import Foundation

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
    case sen(channelID: String)
    case tapt(website: URL, timeZoneIdentifier: String)
}

@MainActor
final class ProgrammeGuide: ObservableObject {
    @Published private(set) var current: Programme?
    @Published private(set) var upcoming: [Programme] = []
    @Published private(set) var message = ""

    private var source: ProgrammeSource?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var taptSchedule: [TaptScheduleEntry] = []
    private var taptFetchedAt: Date?

    func start(channelID: String) { start(source: .sen(channelID: channelID)) }

    func startTapt(website: URL, timeZoneIdentifier: String) {
        start(source: .tapt(website: website, timeZoneIdentifier: timeZoneIdentifier))
    }

    private func start(source newSource: ProgrammeSource) {
        if source != newSource {
            refreshTask?.cancel()
            current = nil; upcoming = []; message = "Loading programme guide…"
            taptSchedule = []; taptFetchedAt = nil; source = newSource
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
        source = nil; taptSchedule = []; taptFetchedAt = nil
        current = nil; upcoming = []; message = ""
    }

    func refresh() {
        guard let source else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let programmes: [Programme]
                switch source {
                case .sen(let channelID): programmes = try await fetchSEN(channelID: channelID)
                case .tapt(let website, let timeZoneIdentifier):
                    programmes = try await fetchTapt(website: website, timeZoneIdentifier: timeZoneIdentifier)
                }
                try Task.checkCancellation()
                guard self.source == source else { return }
                apply(programmes, now: Date())
            } catch is CancellationError { }
            catch {
                guard self.source == source else { return }
                message = current == nil ? "Programme guide unavailable" : "Programme guide could not refresh"
            }
        }
    }

    private func fetchSEN(channelID: String) async throws -> [Programme] {
        var components = URLComponents(string: "https://www.sen.com.au/api/radioplayer")!
        components.queryItems = [URLQueryItem(name: "channelID", value: channelID)]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let guide = try decoder.decode(SENProgrammeResponse.self, from: data)
        var programmes = guide.nowPlayingList
        if let current = guide.nowPlaying, !programmes.contains(where: { $0.id == current.id }) { programmes.append(current) }
        return programmes
    }

    private func fetchTapt(website: URL, timeZoneIdentifier: String) async throws -> [Programme] {
        if let taptFetchedAt, Date().timeIntervalSince(taptFetchedAt) < 15 * 60, !taptSchedule.isEmpty {
            return Self.programmes(from: taptSchedule, timeZoneIdentifier: timeZoneIdentifier, now: Date())
        }
        var request = URLRequest(url: website)
        request.cachePolicy = .reloadRevalidatingCacheData; request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; Wireless Radio)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let schedule = try Self.decodeTaptSchedule(from: html)
        taptSchedule = schedule; taptFetchedAt = Date()
        return Self.programmes(from: schedule, timeZoneIdentifier: timeZoneIdentifier, now: Date())
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
