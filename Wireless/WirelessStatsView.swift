import Charts
import SwiftUI
import UniformTypeIdentifiers

struct WirelessStatsView: View {
    @ObservedObject var store: WirelessListeningStatsStore
    @State private var range: StatsRange = .week
    @State private var showingLast = false
    @State private var expandedStationID: String?
    @State private var jsonExportURL: URL?
    @State private var csvExportURL: URL?
    @State private var importsStats = false
    @State private var transferMessage: String?

    private enum StatsRange: CaseIterable, Identifiable {
        case week, month, year, lifetime

        var id: Self { self }
        var supportsLast: Bool { self != .lifetime }
        var usesHeatmap: Bool { self == .week || self == .month }

        func title(last: Bool, now: Date = Date()) -> String {
            let calendar = Calendar.current
            switch self {
            case .week: return "7 Days"
            case .month:
                let date = last ? calendar.date(byAdding: .month, value: -1, to: now) ?? now : now
                return date.formatted(.dateTime.month(.wide))
            case .year:
                let date = last ? calendar.date(byAdding: .year, value: -1, to: now) ?? now : now
                return date.formatted(.dateTime.year())
            case .lifetime: return "Lifetime"
            }
        }

        var toggleLabels: (String, String)? {
            switch self {
            case .week: ("This Week", "Last Week")
            case .month: ("This Month", "Last Month")
            case .year: ("This Year", "Last Year")
            case .lifetime: nil
            }
        }

        func period(last: Bool) -> WirelessStatsPeriod {
            switch self {
            case .week: last ? .previousWeek : .currentWeek
            case .month: last ? .previousMonth : .currentMonth
            case .year: last ? .previousYear : .currentYear
            case .lifetime: .lifetime
            }
        }

        var previousNoun: String {
            switch self {
            case .week: "week"
            case .month: "month"
            case .year: "year"
            case .lifetime: "period"
            }
        }
    }

    private var hasLastData: Bool {
        range.supportsLast && store.summary(for: range.period(last: true)).listeningSeconds > 0
    }

    private var isLast: Bool { showingLast && hasLastData }

    var body: some View {
        let summary = store.summary(for: range.period(last: isLast))
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rangeSelector
                ViewThatFits(in: .horizontal) {
                    wideLayout(summary).frame(minWidth: 760)
                    compactLayout(summary)
                }
                healthSection
                privacyFooter
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .accessibilityIdentifier("listeningStatsPage")
        .navigationTitle("Listening Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let jsonExportURL {
                        ShareLink(item: jsonExportURL) {
                            Label("Export Backup (JSON)", systemImage: "externaldrive")
                        }
                    }
                    if let csvExportURL {
                        ShareLink(item: csvExportURL) {
                            Label("Export Spreadsheet (CSV)", systemImage: "tablecells")
                        }
                    }
                    Button {
                        importsStats = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Listening stats data options")
            }
        }
        .task { prepareExports() }
        .onChange(of: store.revision) { _, _ in prepareExports() }
        .fileImporter(isPresented: $importsStats, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try store.importJSON(from: url)
                transferMessage = "Listening stats backup imported successfully."
                prepareExports()
            } catch {
                transferMessage = error.localizedDescription
            }
        }
        .alert("Listening Stats", isPresented: Binding(
            get: { transferMessage != nil },
            set: { if !$0 { transferMessage = nil } }
        )) {
            Button("OK", role: .cancel) { transferMessage = nil }
        } message: {
            Text(transferMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }

    private func wideLayout(_ summary: WirelessListeningStatsSummary) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 28) {
                hero(summary)
                topStations(summary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 28) {
                listeningPattern(summary)
                listeningClock(summary)
                habits(summary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func compactLayout(_ summary: WirelessListeningStatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            hero(summary)
            topStations(summary)
            listeningPattern(summary)
            listeningClock(summary)
            habits(summary)
        }
    }

    // Adapted directly from Autohop StatsRangeSelector: centred glass range
    // pills and a compact solid This/Last bar. Overflow remains scrollable for
    // narrow windows and accessibility text sizes without wrapping pill labels.
    private var rangeSelector: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatsRange.allCases) { item in
                        rangePill(item)
                    }
                }
            }
            .scrollClipDisabled()
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .accessibilityIdentifier("statsRangeSelector")

            if let labels = range.toggleLabels, hasLastData {
                HStack(spacing: 0) {
                    periodToggle(labels.0, active: !isLast) { showingLast = false }
                    periodToggle(labels.1, active: isLast) { showingLast = true }
                }
                .padding(3)
                .background(Color.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rangePill(_ item: StatsRange) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                range = item
            }
        } label: {
            let pill = Text(item.title(last: item == range && isLast))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(range == item ? Color.white : Color.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .fixedSize()
            if range == item {
                pill.glassEffect(.regular.tint(.purple), in: Capsule())
            } else {
                pill.glassEffect(in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statsRange-\(item)")
        .accessibilityAddTraits(range == item ? .isSelected : [])
    }

    private func periodToggle(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(active ? Color.purple : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func hero(_ summary: WirelessListeningStatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(range == .lifetime
                     ? "Time listened since \(store.healthSnapshot.trackingStarted.formatted(date: .abbreviated, time: .omitted))"
                     : "Time listened")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formatDuration(summary.listeningSeconds))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.purple)
                    .contentTransition(.numericText())
            }
            Divider().overlay(Color.white.opacity(0.08))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12, alignment: .leading)], spacing: 12) {
                heroStat("\(summary.sessionCount)", summary.sessionCount == 1 ? "listening session" : "listening sessions")
                heroStat("\(summary.stationCount)", summary.stationCount == 1 ? "station heard" : "stations heard")
                heroStat(streakText, "current streak · all time")
            }
            Text("A streak day means at least 1 minute of rendered audio. Buffering and reconnection time are excluded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsCard()
    }

    private var streakText: String {
        let days = store.currentStreakDays
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topStations(_ summary: WirelessListeningStatsSummary) -> some View {
        let stations = summary.topStations(limit: 8)
        let maximum = stations.first?.seconds ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeading("Top Stations", icon: "trophy")
                Spacer()
                if summary.stationCount > stations.count {
                    NavigationLink {
                        WirelessTopStationsView(store: store, period: range.period(last: isLast), periodName: range.previousNoun)
                    } label: {
                        Label("Show All", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                }
            }
            if stations.isEmpty {
                emptyText("Start listening and your top stations will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(stations.enumerated()), id: \.element.snapshot.id) { index, item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedStationID = expandedStationID == item.snapshot.id ? nil : item.snapshot.id
                            }
                        } label: {
                            stationRow(rank: index + 1, item: item, maximum: maximum)
                        }
                        .buttonStyle(.plain)
                        if expandedStationID == item.snapshot.id {
                            stationDetail(item.snapshot, summary: summary)
                        }
                        if index < stations.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 72)
                        }
                    }
                }
                .statsCard()
            }
        }
    }

    private func stationRow(
        rank: Int,
        item: (snapshot: WirelessStationStatsSnapshot, seconds: TimeInterval),
        maximum: TimeInterval,
        movement: Int? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20)
            stationArtwork(item.snapshot)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.snapshot.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if let movement {
                        Text(movement > 0 ? "▲\(movement)" : "▼\(-movement)")
                            .font(.caption2.bold()).foregroundStyle(movement > 0 ? .teal : .secondary)
                    }
                }
                GeometryReader { proxy in
                    Capsule().fill(Color.white.opacity(0.07))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.purple)
                                .frame(width: proxy.size.width * CGFloat(maximum > 0 ? item.seconds / maximum : 0))
                        }
                }
                .frame(height: 5)
                HStack {
                    Text([item.snapshot.network, item.snapshot.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .lineLimit(1)
                    Spacer()
                    Text(formatDuration(item.seconds)).monospacedDigit()
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func stationDetail(_ station: WirelessStationStatsSnapshot, summary: WirelessListeningStatsSummary) -> some View {
        let sessions = summary.sessions.values.filter { $0.stationID == station.id }
        let seconds = summary.perStationSeconds[station.id] ?? 0
        let average = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.renderedSeconds } / Double(sessions.count)
        let longest = sessions.map(\.renderedSeconds).max() ?? 0
        let last = sessions.map(\.endedAt).max()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12, alignment: .leading)], spacing: 12) {
            detailStat(formatDuration(average), "average session")
            detailStat(formatDuration(longest), "longest session")
            detailStat(summary.listeningSeconds > 0 ? "\(Int((seconds / summary.listeningSeconds * 100).rounded()))%" : "0%", "of all listening")
            detailStat(last?.formatted(.relative(presentation: .named)) ?? "—", "last listened")
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func detailStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func listeningPattern(_ summary: WirelessListeningStatsSummary) -> some View {
        if range.usesHeatmap { heatmap(summary) } else { trend(summary) }
    }

    private func heatmap(_ summary: WirelessListeningStatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Listening Heatmap", icon: "calendar")
            VStack(alignment: .leading, spacing: 10) {
                WirelessListeningHeatmap(days: summary.days)
                if let busiest = summary.days.max(by: { $0.listeningSeconds < $1.listeningSeconds }),
                   busiest.listeningSeconds > 0,
                   let date = statsDate(busiest.dayKey) {
                    Text("Busiest day: \(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(formatDuration(busiest.listeningSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14).frame(maxWidth: .infinity).statsCard()
        }
    }

    private func trend(_ summary: WirelessListeningStatsSummary) -> some View {
        let months = monthTotals(summary)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Listening Over Time", icon: "chart.bar")
            if months.allSatisfy({ $0.seconds == 0 }) {
                emptyText("No listening recorded in this period yet.")
            } else {
                Chart(months, id: \.date) { item in
                    BarMark(x: .value("Month", item.date, unit: .month), y: .value("Hours", item.seconds / 3600))
                        .foregroundStyle(Color.purple.gradient).cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel { if let hours = value.as(Double.self) { Text("\(Int(hours))h") } }
                    }
                }
                .frame(height: 180).padding(14).statsCard()
            }
        }
    }

    private func listeningClock(_ summary: WirelessListeningStatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Listening Clock", icon: "clock")
            VStack(spacing: 10) {
                if summary.hourSeconds.allSatisfy({ $0 == 0 }) {
                    Text("No listening recorded in this period yet.").foregroundStyle(.secondary)
                } else {
                    WirelessListeningClock(hourSeconds: summary.hourSeconds).frame(height: 230)
                    if let maximum = summary.hourSeconds.max(), maximum > 0,
                       let hour = summary.hourSeconds.firstIndex(of: maximum) {
                        Text("Peak listening: \(hourName(hour))–\(hourName((hour + 1) % 24))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity).statsCard()
        }
    }

    private func habits(_ summary: WirelessListeningStatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("How You Listen", icon: "waveform")
            VStack(spacing: 0) {
                habitRow("Average Session", value: formatDuration(summary.averageSessionSeconds))
                divider
                habitRow("Longest Session", value: formatDuration(summary.longestSessionSeconds))
                ForEach(WirelessListeningMode.allCases, id: \.rawValue) { mode in
                    if let seconds = summary.modeSeconds[mode.rawValue], seconds > 0 {
                        divider
                        habitRow(mode.title, value: formatDuration(seconds), share: share(seconds, of: summary.listeningSeconds))
                    }
                }
                ForEach(WirelessAudioRouteCategory.allCases, id: \.rawValue) { route in
                    if let seconds = summary.routeSeconds[route.rawValue], seconds > 0 {
                        divider
                        habitRow(route.title, value: formatDuration(seconds), share: share(seconds, of: summary.listeningSeconds))
                    }
                }
            }
            .statsCard()
        }
    }

    private func habitRow(_ label: String, value: String, share: String? = nil) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            if let share { Text(share).font(.caption).foregroundStyle(.tertiary) }
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var healthSection: some View {
        let health = store.healthSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Stats Health", icon: "checkmark.shield")
            VStack(spacing: 0) {
                healthRow("Status", health.status)
                divider
                healthRow("Recorded days", "\(health.recordedDays)")
                divider
                healthRow("Tracking since", health.trackingStarted.formatted(date: .abbreviated, time: .omitted))
                if let lastSave = health.lastLocalSave {
                    divider
                    healthRow("Last local save", lastSave.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .statsCard()
        }
    }

    private func healthRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var privacyFooter: some View {
        Label(
            "Your listening stats are private and kept on this device. They are never sent to Wireless.",
            systemImage: "lock.shield"
        )
        .font(.caption).foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    private func stationArtwork(_ station: WirelessStationStatsSnapshot) -> some View {
        AsyncImage(url: URL(string: station.artworkURL)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.4), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "radio").foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func sectionHeading(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.title3.bold())
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).statsCard()
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 14)
    }

    private func share(_ seconds: TimeInterval, of total: TimeInterval) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((seconds / total * 100).rounded()))%"
    }

    private func monthTotals(_ summary: WirelessListeningStatsSummary) -> [(date: Date, seconds: TimeInterval)] {
        summary.days.reduce(into: [Date: TimeInterval]()) { totals, day in
            guard let date = statsDate(day.dayKey),
                  let month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) else { return }
            totals[month, default: 0] += day.listeningSeconds
        }
        .sorted { $0.key < $1.key }
        .map { ($0.key, $0.value) }
    }

    private func hourName(_ hour: Int) -> String {
        switch hour {
        case 0: "12am"
        case 1...11: "\(hour)am"
        case 12: "12pm"
        default: "\(hour - 12)pm"
        }
    }

    private func prepareExports() {
        jsonExportURL = try? store.makeJSONExport()
        csvExportURL = try? store.makeCSVExport()
    }
}

private struct WirelessTopStationsView: View {
    @ObservedObject var store: WirelessListeningStatsStore
    let period: WirelessStatsPeriod
    let periodName: String

    var body: some View {
        let summary = store.summary(for: period)
        let stations = summary.topStations(limit: 50)
        let previous = store.previousPeriodStationSeconds(for: period)
        let previousRanks = Dictionary(uniqueKeysWithValues: (previous ?? [:])
            .filter { $0.value > 0 }.sorted { $0.value > $1.value }.enumerated().map { ($0.element.key, $0.offset + 1) })
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element.snapshot.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                        AsyncImage(url: URL(string: item.snapshot.artworkURL)) { image in image.resizable().scaledToFill() } placeholder: {
                            Image(systemName: "radio").frame(maxWidth: .infinity, maxHeight: .infinity).background(.purple.opacity(0.25))
                        }
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.snapshot.name).font(.subheadline.bold()).lineLimit(1)
                            Text(item.snapshot.network).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let old = previousRanks[item.snapshot.id] {
                            let movement = old - (index + 1)
                            if movement != 0 {
                                Text(movement > 0 ? "▲\(movement)" : "▼\(-movement)")
                                    .font(.caption2.bold()).foregroundStyle(movement > 0 ? .teal : .secondary)
                            }
                        } else if previous != nil {
                            Text("NEW").font(.caption2.bold()).foregroundStyle(.purple)
                        }
                        Text(formatDuration(item.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if index < stations.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 70) }
                }
            }
            .statsCard().padding(20).frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Top Stations")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if previous != nil {
                Text("▲▼ rank change vs. the previous \(periodName)")
                    .font(.caption).foregroundStyle(.tertiary).padding(8)
            }
        }
    }
}

private struct WirelessListeningHeatmap: View {
    let days: [WirelessDayStats]

    private struct Cell: Identifiable { let id: Int; let seconds: TimeInterval? }

    var body: some View {
        let weeks = columns()
        let size: CGFloat = weeks.count <= 7 ? 30 : 19
        let spacing: CGFloat = weeks.count <= 7 ? 4 : 3
        let maximum = days.map(\.listeningSeconds).max() ?? 0
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(week) { cell in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colour(cell.seconds, maximum: maximum))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func columns() -> [[Cell]] {
        var values: [TimeInterval?] = []
        if let first = days.first, let date = statsDate(first.dayKey) {
            let padding = (Calendar.current.component(.weekday, from: date) - 2 + 7) % 7
            values.append(contentsOf: repeatElement(nil, count: padding))
        }
        values.append(contentsOf: days.map(\.listeningSeconds))
        while !values.count.isMultiple(of: 7) { values.append(nil) }
        return stride(from: 0, to: values.count, by: 7).map { start in
            (start..<min(start + 7, values.count)).map { Cell(id: $0, seconds: values[$0]) }
        }
    }

    private func colour(_ seconds: TimeInterval?, maximum: TimeInterval) -> Color {
        guard let seconds else { return .clear }
        guard seconds > 0, maximum > 0 else { return Color.white.opacity(0.06) }
        return Color.purple.opacity(0.25 + 0.75 * sqrt(seconds / maximum))
    }
}

private struct WirelessListeningClock: View {
    let hourSeconds: [TimeInterval]

    var body: some View {
        ZStack {
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let maximumRadius = min(size.width, size.height) / 2 - 4
                let maximum = hourSeconds.max() ?? 0
                for scale in [0.5, 1.0] {
                    let radius = maximumRadius * scale
                    context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.08)))
                }
                guard maximum > 0 else { return }
                for hour in 0..<24 where hourSeconds[hour] > 0 {
                    let radius = 5 + (maximumRadius - 5) * sqrt(hourSeconds[hour] / maximum)
                    var path = Path()
                    path.move(to: centre)
                    path.addArc(center: centre, radius: radius,
                                startAngle: .degrees(Double(hour) / 24 * 360 - 89),
                                endAngle: .degrees(Double(hour + 1) / 24 * 360 - 91), clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(.purple.opacity(0.9)))
                }
            }
            .padding(18)
            VStack { Text("12am"); Spacer(); Text("12pm") }
            HStack { Text("6pm"); Spacer(); Text("6am") }
        }
        .font(.caption2).foregroundStyle(.tertiary)
    }
}

private struct StatsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

private extension View {
    func statsCard() -> some View { modifier(StatsCardModifier()) }
}

private func statsDate(_ key: String) -> Date? {
    let values = key.split(separator: "-").compactMap { Int($0) }
    guard values.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
    if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(total % 60)s"
}

#if DEBUG
/// Isolated data for exercising the real period controls without altering listening history.
struct WirelessStatsPreview: View {
    @StateObject private var store: WirelessListeningStatsStore

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-preview-\(UUID().uuidString).json")
        let store = WirelessListeningStatsStore(fileURL: url)
        let now = Date()
        for date in [now, Calendar.current.date(byAdding: .day, value: -7, to: now)!,
                     Calendar.current.date(byAdding: .month, value: -1, to: now)!,
                     Calendar.current.date(byAdding: .year, value: -1, to: now)!] {
            store.recordRendered(seconds: 120, station: .sen, mode: .live, route: .other, endedAt: date)
            store.endSession(reason: .paused)
        }
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack { WirelessStatsView(store: store) }
            .tint(.purple)
    }
}
#endif
