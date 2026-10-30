import SwiftUI

struct SongRecognitionView: View {
    @ObservedObject var recognition: SongRecognition
    let stationName: String
    let identify: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(stationName).font(.headline).foregroundStyle(.secondary)
                    result
                    if !recognition.sourceExplanation.isEmpty {
                        Text(recognition.sourceExplanation).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Shazam receives an audio fingerprint, not a recording. Identification needs an internet connection and may recognise music in adverts or behind speech.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !recognition.state.isWorking {
                        Button("Identify again", systemImage: "shazam.logo", action: identify)
                            .buttonStyle(.borderedProminent).tint(.purple)
                    } else {
                        Button("Cancel identification") { recognition.cancel() }
                            .buttonStyle(.bordered)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Identify song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.purple)
        .onDisappear { recognition.cancel() }
    }

    @ViewBuilder private var result: some View {
        switch recognition.state {
        case .ready:
            status("Identify a song", detail: "Play a station, then identify the song in its live broadcast.", symbol: "shazam.logo")
        case .listening, .matching:
            ProgressView().controlSize(.large).tint(.purple)
            Text(recognition.state == .listening ? "Sampling the stream…" : "Checking with Shazam…")
                .font(.title2.bold()).accessibilityIdentifier("songRecognitionProgress")
            Text("Radio playback continues. This can take up to 30 seconds.").foregroundStyle(.secondary)
        case .found(let song):
            AsyncImage(url: song.artworkURL) { image in image.resizable().scaledToFit() } placeholder: {
                Image(systemName: "music.note").resizable().scaledToFit().padding(50).foregroundStyle(.purple)
            }
            .frame(width: 200, height: 200).clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(song.title).font(.title2.bold()).accessibilityIdentifier("identifiedSongTitle")
                Text(song.artist).font(.title3).foregroundStyle(.secondary)
                Text("Identified with Shazam").font(.caption).foregroundStyle(.secondary)
            }
            if let url = song.appleMusicURL {
                Link(destination: url) { Label("Open in Apple Music", systemImage: "music.note") }
                    .buttonStyle(.borderedProminent).tint(.purple)
            } else if let url = song.shazamURL {
                Link("View on Shazam", destination: url).buttonStyle(.bordered)
            }
            if song.shazamID != nil {
                Button {
                    Task { await recognition.saveToShazam() }
                } label: {
                    Label(recognition.saved ? "Saved to Shazam" : recognition.saving ? "Saving…" : "Save to Shazam",
                          systemImage: recognition.saved ? "checkmark" : "plus")
                }
                .buttonStyle(.bordered).disabled(recognition.saving || recognition.saved)
            }
            if let message = recognition.saveMessage { Text(message).font(.footnote) }
        case .noMatch:
            status("No song found", detail: "Try again during a clear section of music. Live performances, talk-over and some recordings may not match.", symbol: "music.note")
        case .failed(let message):
            status("Unable to identify", detail: message, symbol: "exclamationmark.circle")
        }
    }
    private func status(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.purple).accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
/// Same isolated visual-fixture approach as WirelessMetadataPreview. No audio
/// capture, network matching or library write is performed by this preview.
struct WirelessSongRecognitionPreview: View {
    @StateObject private var recognition: SongRecognition
    init() {
        let mode = ProcessInfo.processInfo.environment["WIRELESS_SONG_PREVIEW"] ?? "found"
        let song = RecognisedSong(title: "Never Tear Us Apart", artist: "INXS",
            appleMusicURL: URL(string: "https://music.apple.com/au/"), shazamID: "12345")
        let state: SongRecognitionState = mode == "no-match" ? .noMatch
            : mode == "error" ? .failed("This stream could not supply audio for identification. Try another stream in Audio Controls.")
            : mode == "listening" ? .listening : .found(song)
        _recognition = StateObject(wrappedValue: SongRecognition(previewState: state))
    }
    var body: some View {
        SongRecognitionView(recognition: recognition, stationName: "Wireless Radio Melbourne", identify: {})
    }
}
#endif
