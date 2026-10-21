import SwiftUI

struct WirelessListeningHistoryView: View {
    @ObservedObject var store: WirelessListeningStatsStore
    @ObservedObject var player: MobilePlayer
    @ObservedObject private var library: StationLibrary
    @State private var searchText = ""

    init(store: WirelessListeningStatsStore, player: MobilePlayer) {
        self.store = store
        self.player = player
        self.library = player.library
    }

    private var summary: WirelessListeningHistorySummary {
        store.listeningHistory()
    }

    private var filteredItems: [WirelessListeningHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return summary.items }
        return summary.items.filter { item in
            [item.station.name, item.station.network, item.station.location]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var groupedItems: [(title: String, items: [WirelessListeningHistoryItem])] {
        let grouped = Dictionary(grouping: filteredItems) { item in
            Calendar.current.startOfDay(for: item.session.endedAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (dayTitle($0.key), $0.value.sorted { $0.session.endedAt > $1.session.endedAt }) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                historyStat(title: "Listening Time", value: formatDuration(summary.listeningSeconds))
                historyStat(title: "Sessions", value: "\(summary.sessionCount)")
            }
            .padding(.horizontal, 16)

            if groupedItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Listening History" : "No Results",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(searchText.isEmpty
                        ? "Stations you listen to for at least one minute will appear here, newest first."
                        : "Try a different station, network or location.")
                )
                .frame(maxHeight: .infinity)
            } else {
                historyList
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Listening History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .preferredColorScheme(.dark)
        .tint(.purple)
        .accessibilityIdentifier("listeningHistoryPage")
    }

    private var historyList: some View {
        List {
            ForEach(groupedItems, id: \.title) { group in
                Section {
                    ForEach(group.items) { item in
                        let station = resolvedStation(for: item)
                        let isCurrent = store.activeSessionID == item.id && player.requested
                        Button {
                            if let station { player.playStation(station) }
                        } label: {
                            WirelessListeningHistoryRow(item: item, isCurrent: isCurrent, isAvailable: station != nil)
                        }
                        .buttonStyle(.plain)
                        .disabled(station == nil)
                        .listRowBackground(isCurrent ? Color.purple.opacity(0.10) : Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if let station, !isCurrent {
                                Button { player.playStation(station) } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let station {
                                Button { library.toggle(station) } label: {
                                    Label(
                                        library.contains(station) ? "Unfavourite" : "Favourite",
                                        systemImage: library.contains(station) ? "heart.slash" : "heart"
                                    )
                                }
                                .tint(.purple)
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .historyGlassCard(cornerRadius: 16)
    }

    private func historyStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .historyGlassCard(cornerRadius: 12)
    }

    private func resolvedStation(for item: WirelessListeningHistoryItem) -> DirectoryStation? {
        let candidates = library.stations + library.favourites + library.recents
        guard let station = candidates.first(where: { $0.id == item.station.id }),
              library.available(station), station.preferredStream != nil else { return nil }
        return station
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: Date()) {
            return day.formatted(.dateTime.day().month(.abbreviated))
        }
        return day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}

private struct WirelessListeningHistoryRow: View {
    let item: WirelessListeningHistoryItem
    let isCurrent: Bool
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            historyArtwork
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.station.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(isCurrent ? "Playing" : "Listened")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isCurrent ? Color.purple : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isCurrent ? Color.purple : Color.white).opacity(0.10), in: Capsule())
                }
                let stationDetail = [item.station.network, item.station.location].filter { !$0.isEmpty }.joined(separator: " · ")
                if !stationDetail.isEmpty {
                    Text(stationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(sessionDetail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if !isAvailable {
                    Text("No longer available in the directory")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var historyArtwork: some View {
        if let url = URL(string: item.station.artworkURL), url.scheme == "https" {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                artworkFallback
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            artworkFallback
        }
    }

    private var artworkFallback: some View {
        ZStack {
            Color.purple.opacity(0.15)
            Image(systemName: "waveform")
                .font(.headline)
                .foregroundStyle(.purple)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var sessionDetail: String {
        let seconds = Int(item.session.renderedSeconds.rounded())
        let minutes = max(1, seconds / 60)
        let duration = minutes >= 60
            ? "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m")
            : "\(minutes)m"
        let start = item.session.startedAt.formatted(date: .omitted, time: .shortened)
        let end = item.session.endedAt.formatted(date: .omitted, time: .shortened)
        return "\(duration) listened · \(start)–\(end)"
    }
}

private extension View {
    func historyGlassCard(cornerRadius: CGFloat) -> some View {
        glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
