import SwiftUI

struct SongRecognitionView: View {
    @ObservedObject var recognition: SongRecognition
    let stationName: String
    @ObservedObject var history: ShazamHistoryStore
    let identify: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 26) {
                        result(wide: geometry.size.width >= 680 && !typeSize.isAccessibilitySize)
                        if let error = history.persistenceError {
                            Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                        }
                        if usesSeparateConnection {
                            Label(recognition.sourceExplanation, systemImage: "network")
                                .font(.footnote).foregroundStyle(.secondary).padding(16)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                        }
                        controls
                        DisclosureGroup("About identification") {
                            VStack(alignment: .leading, spacing: 12) {
                                if !usesSeparateConnection && !recognition.sourceExplanation.isEmpty { Text(recognition.sourceExplanation) }
                                Text("Shazam receives an audio fingerprint, not a recording. Identification needs an internet connection and may recognise music in adverts or behind speech.")
                            }
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline).padding(18)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .frame(maxWidth: 860).padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .background(ShazamBackdrop())
            }
            .navigationTitle("Identify song").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ShazamHistoryView(history: history) } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("recognitionHistory")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        recognition.cancel(reason: "sheet-dismissed"); dismiss()
                    }.labelStyle(.iconOnly)
                }
            }
        }
        .preferredColorScheme(.dark).tint(.purple)
    }
    private var usesSeparateConnection: Bool { recognition.sourceExplanation.localizedCaseInsensitiveContains("separate connection") }
    @ViewBuilder private func result(wide: Bool) -> some View {
        switch recognition.state {
        case .found(let song):
            ShazamSongHero(song: song, stationName: stationName, wide: wide)
        case .ready:
            status("Discover what’s playing", detail: "Play a station, then identify a song without interrupting your radio.", symbol: "shazam.logo")
        case .listening, .matching:
            status(recognition.state == .listening ? "Sampling the stream…" : "Listening and matching with Shazam…",
                   detail: "Keep listening. Your radio keeps playing while Shazam finds the song.", symbol: "shazam.logo", working: true)
        case .noMatch:
            status("No song found", detail: "Try again during a clear section of music. Live performances, talk-over and some recordings may not match.", symbol: "music.note")
        case .failed(let message):
            status("Unable to identify", detail: message, symbol: "exclamationmark.circle")
        }
    }
    private func status(_ title: String, detail: String, symbol: String, working: Bool = false) -> some View {
        VStack(spacing: 22) {
            Label(stationName, systemImage: "radio").font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: symbol).font(.system(size: 64, weight: .medium))
                .foregroundStyle(.white).frame(width: 148, height: 148)
                .glassEffect(.regular.tint(.purple.opacity(0.45)), in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: working && !reduceMotion)
                .padding(.vertical, 12).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(working ? "songRecognitionProgress" : "recognitionStatusTitle")
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if working {
                ProgressView().tint(.purple).accessibilityLabel("Identifying song")
                Text("Up to 30 seconds · Cancel any time").font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center).padding(26).frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.purple.opacity(0.06)), in: RoundedRectangle(cornerRadius: 30))
    }
    private var controls: some View {
        Group {
            if recognition.state.isWorking {
                Button("Cancel identification", systemImage: "xmark", action: { recognition.cancel() }).buttonStyle(.glass)
            } else {
                Button(recognition.state == .ready ? "Identify song" : "Identify again", systemImage: "shazam.logo", action: identify)
                    .buttonStyle(.glassProminent)
            }
        }
        .font(.headline).controlSize(.large).buttonBorderShape(.capsule)
    }
}

#if DEBUG
/// Isolated visual fixtures never write to production history or capture audio.
struct WirelessSongRecognitionPreview: View {
    @StateObject private var recognition: SongRecognition
    @StateObject private var history: ShazamHistoryStore
    init() {
        let mode = ProcessInfo.processInfo.environment["WIRELESS_SONG_PREVIEW"] ?? "found"
        let song = ShazamPreviewData.song
        let state: SongRecognitionState = mode == "no-match" ? .noMatch
            : mode == "error" ? .failed("This stream could not supply audio for identification. Try another stream in Audio Controls.")
            : mode == "listening" ? .listening : .found(song)
        _recognition = StateObject(wrappedValue: SongRecognition(previewState: state))
        let store = ShazamPreviewData.history(populated: mode != "history-empty")
        _history = StateObject(wrappedValue: store)
    }
    var body: some View {
        if ProcessInfo.processInfo.environment["WIRELESS_SONG_PREVIEW"]?.hasPrefix("history") == true {
            NavigationStack { ShazamHistoryView(history: history) }
                .preferredColorScheme(.dark).tint(.purple)
        } else {
            SongRecognitionView(recognition: recognition, stationName: "Wireless Radio Melbourne", history: history, identify: {})
        }
    }
}
#endif
