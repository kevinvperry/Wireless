import SwiftUI

/// Wireless's Autohop-derived purple glass vocabulary, with container-relative
/// artwork sizing and native controls rather than device-model assumptions.
struct ShazamBackdrop: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [.purple.opacity(0.24), .black, .indigo.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.purple.opacity(0.15)).frame(width: 360, height: 360).blur(radius: 90).offset(x: 120, y: -240)
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ShazamArtwork: View {
    let song: RecognisedSong
    var cornerRadius: CGFloat = 28
    var body: some View {
        AsyncImage(url: song.artworkURL) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                GeometryReader { geometry in
                  ZStack {
                    LinearGradient(colors: [.purple.opacity(0.8), .indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").resizable().scaledToFit().padding(geometry.size.width * 0.32).foregroundStyle(.white.opacity(0.75))
                  }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .purple.opacity(0.15), radius: 28, y: 12)
        .accessibilityHidden(true)
    }
}

struct ShazamSongLinks: View {
    let song: RecognisedSong
    var body: some View {
        VStack(spacing: 12) {
            if let url = song.appleMusicURL {
                Link(destination: url) {
                    Label("Open in Apple Music", systemImage: "music.note").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).tint(.purple)
                .accessibilityIdentifier("openInAppleMusic")
            }
            if let url = song.shazamURL {
                Link(destination: url) {
                    Label("Open in Shazam", systemImage: "shazam.logo").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("openInShazam")
                .accessibilityHint("Opens this song in Shazam, or its website if the app is unavailable")
            }
        }
        .font(.headline).controlSize(.large).buttonBorderShape(.capsule)
    }
}

struct ShazamSongHero: View {
    let song: RecognisedSong
    let stationName: String
    var identifiedAt: Date?
    let wide: Bool
    var body: some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: 28) {
                    cover.frame(maxWidth: .infinity)
                    information.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 26) {
                    cover.frame(maxWidth: 420)
                    information
                }
            }
        }
    }
    private var cover: some View {
        ShazamArtwork(song: song)
            .overlay(alignment: .bottomLeading) {
                Label("Identified with Shazam", systemImage: "shazam.logo")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                    .glassEffect(.regular, in: Capsule()).padding(14)
            }
            .accessibilityIdentifier("identifiedSongArtwork")
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(song.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("identifiedSongTitle").accessibilityAddTraits(.isHeader)
                Text(song.artist).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label(stationName, systemImage: "radio").font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let identifiedAt {
                    Text(identifiedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ShazamSongLinks(song: song)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
