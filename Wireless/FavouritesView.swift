import SwiftUI

struct FavouritesView: View {
    @ObservedObject var library: StationLibrary
    let currentID: String
    let isPlaying: Bool
    let play: (DirectoryStation) -> Void
    let browse: () -> Void
    let close: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive

    private var isReordering: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let metrics = WirelessLayoutMetrics(width: proxy.size.width)
                Group {
                if library.favourites.isEmpty {
                    ContentUnavailableView {
                        Label("No favourites yet", systemImage: "heart")
                    } description: {
                        Text("Save a station for quick access here.")
                    } actions: {
                        Button("Browse Stations", action: browse)
                    }
                } else {
                    VStack(spacing: 0) {
                        reorderBar(metrics: metrics)
                        List {
                            ForEach(Array(library.favourites.enumerated()), id: \.element.id) { index, station in
                                favouriteRow(station, position: index + 1, metrics: metrics)
                                    .listRowBackground(currentID == station.id ? Color.purple.opacity(0.08) : Color.clear)
                            }
                            .onMove(perform: library.moveFavourites)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.editMode, $editMode)
                    }
                }
            }
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: horizontalSizeClass == .regular ? 18 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: horizontalSizeClass == .regular ? 44 : 36,
                                   height: horizontalSizeClass == .regular ? 44 : 36)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.regularMaterial)
    }

    private func reorderBar(metrics: WirelessLayoutMetrics) -> some View {
        HStack(spacing: metrics.rowSpacing) {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    editMode = isReordering ? .inactive : .active
                }
            } label: {
                Label(isReordering ? "Done" : "Reorder",
                      systemImage: isReordering ? "checkmark" : "arrow.up.arrow.down")
                    .font(.system(size: metrics.compactControlFont, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .glassEffect(isReordering ? .regular.tint(.purple) : .regular, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reorderFavourites")

            if isReordering {
                Text("Drag stations to set their order")
                    .font(.system(size: metrics.secondary))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func favouriteRow(_ station: DirectoryStation, position: Int, metrics: WirelessLayoutMetrics) -> some View {
        HStack(spacing: metrics.rowSpacing) {
            if currentID == station.id && isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: metrics.secondary, weight: .bold)).foregroundStyle(.purple)
                    .frame(width: metrics.markerWidth)
            } else {
                Text("\(position)")
                    .font(.system(size: metrics.secondary, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.markerWidth)
            }

            StationImage(station: station)
                .frame(width: metrics.artwork, height: metrics.artwork)

            Button { play(station) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.system(size: metrics.primary, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text([station.network, station.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: metrics.secondary))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if currentID == station.id {
                        Label(isPlaying ? "Playing" : "Selected", systemImage: isPlaying ? "waveform" : "radio")
                            .font(.system(size: metrics.secondary)).foregroundStyle(.purple)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isReordering || !library.available(station) || station.preferredStream == nil)
            .accessibilityLabel("Play \(station.name)")

            if !isReordering {
                Button { library.toggle(station) } label: {
                    Image(systemName: "heart.fill")
                        .font(.title3.bold()).foregroundStyle(.purple)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(station.name) from Favourites")
            }
        }
        .padding(.vertical, metrics.rowPadding)
        .contentShape(Rectangle())
    }
}
