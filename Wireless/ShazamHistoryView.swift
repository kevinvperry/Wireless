import SwiftUI

struct ShazamHistoryView: View {
    @ObservedObject var history: ShazamHistoryStore
    @State private var search = ""
    @State private var confirmClear = false
    private var filtered: [ShazamHistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter {
            [$0.song.title, $0.song.artist, $0.stationName].contains { $0.localizedStandardContains(query) }
        }
    }
    private struct Day: Identifiable { let id: Date; let entries: [ShazamHistoryEntry] }
    private var groups: [Day] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.identifiedAt) }
        return grouped.keys.sorted(by: >).map { Day(id: $0, entries: grouped[$0] ?? []) }
    }
    var body: some View {
        List {
            if let error = history.persistenceError {
                Section { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
                    .listRowBackground(Color.clear)
            }
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("Your discoveries start here", systemImage: "shazam.logo")
                } description: {
                    Text("Songs you identify in Wireless appear here, ready to open in Apple Music or Shazam.")
                }
                .listRowBackground(Color.clear).accessibilityIdentifier("shazamHistoryEmpty")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
            } else {
                Section {
                    Label("\(history.entries.count) identified \(history.entries.count == 1 ? "song" : "songs")", systemImage: "shazam.logo")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink {
                                ShazamHistoryDetailView(entry: entry, history: history)
                            } label: {
                                HStack(spacing: 14) {
                                    ShazamArtwork(song: entry.song, cornerRadius: 12).frame(width: 64, height: 64)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.song.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(entry.song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                        Text(entry.stationName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .accessibilityIdentifier("shazamHistoryEntry")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions { Button("Delete", role: .destructive) { history.remove(entry.id) } }
                        }
                    } header: { Text(group.id, format: .dateTime.weekday(.wide).day().month(.wide).year()) }
                }
            }
        }
        .frame(maxWidth: 820).frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden).background(ShazamBackdrop())
        .navigationTitle("Shazam History").navigationBarTitleDisplayMode(.inline)
        .task { history.retryLoading() }
        .searchable(text: $search, prompt: "Search songs, artists or stations")
        .tint(.purple).preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear history", systemImage: "trash", role: .destructive) { confirmClear = true }
                } label: { Label("History options", systemImage: "ellipsis") }
                .disabled(history.entries.isEmpty && history.persistenceError == nil)
                .accessibilityIdentifier("shazamHistoryOptions")
            }
        }
        .alert("Clear Shazam History?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the history saved in Wireless on this device. It does not change Shazam or your music libraries.") }
    }
}

private struct ShazamHistoryDetailView: View {
    let entry: ShazamHistoryEntry
    @ObservedObject var history: ShazamHistoryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmDelete = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    ShazamSongHero(song: entry.song, stationName: entry.stationName, identifiedAt: entry.identifiedAt,
                                   wide: geometry.size.width >= 680 && !typeSize.isAccessibilitySize)
                    if let error = history.persistenceError { Text(error).font(.footnote).foregroundStyle(.orange) }
                }
                .frame(maxWidth: 860).padding(22).frame(maxWidth: .infinity)
            }.background(ShazamBackdrop())
        }
        .navigationTitle("Identified song").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete from history", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .alert("Delete this identification?", isPresented: $confirmDelete) {
            Button("Delete from history", role: .destructive) { if history.remove(entry.id) { dismiss() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

#if DEBUG
@MainActor enum ShazamPreviewData {
    static let song = RecognisedSong(title: "My Sharona", artist: "The Knack",
        artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/15/9b/52/159b52b5-b1fc-3168-c16d-b4d593f91aed/00602537636143.rgb.jpg/632x632bb-60.jpg"),
        appleMusicURL: URL(string: "https://music.apple.com/au/"),
        shazamURL: URL(string: "https://www.shazam.com/track/12345"), shazamID: "12345")
    static func history(populated: Bool) -> ShazamHistoryStore {
        let store = ShazamHistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ShazamPreview-\(UUID().uuidString)/history.json"))
        if populated {
            store.record(song, stationID: "preview", stationName: "Wireless Radio Melbourne")
            store.record(RecognisedSong(title: "Never Tear Us Apart", artist: "INXS", appleMusicURL: song.appleMusicURL,
                                       shazamURL: song.shazamURL, shazamID: "12346"),
                         stationID: "preview-tradie", stationName: "Triple M Tradie Radio", at: Date().addingTimeInterval(-86_400))
        }
        return store
    }
}
#endif
