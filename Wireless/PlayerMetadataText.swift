import SwiftUI

/// Adapted from Autohop PlayerView.episodeCopyView: primary content above its source.
struct PlayerMetadataText: View {
    let stationName: String
    let stationDetail: String
    let track: StreamTrackMetadata?
    let contentScale: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Text(track?.displayTitle ?? stationName)
                .font(.system(size: 16 * contentScale, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(track == nil ? "currentStationTitle" : "currentTrackTitle")
            Text(track == nil ? stationDetail : stationName)
                .font(.system(size: 12 * contentScale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("playerSecondaryTitle")
        }
    }
}

#if DEBUG
/// Deterministic rendering fixture for interface tests; never starts an audio stream.
struct WirelessMetadataPreview: View {
    @State private var track = StreamTrackMetadataParser.validated(title: "Never Tear Us Apart", artist: "INXS")

    var body: some View {
        GeometryReader { geometry in
            let metrics = WirelessLayoutMetrics(width: geometry.size.width)
            VStack(spacing: 28) {
                Spacer()
                PlayerMetadataText(
                    stationName: "Triple M Melbourne 105.1",
                    stationDetail: "Triple M · Melbourne",
                    track: track,
                    contentScale: metrics.contentScale
                )
                HStack {
                    Button("Commercial break") {
                        let marker = "Asset Stop 00:00 2026-10-14T07:59:59.918Z"
                        track = StreamTrackMetadataParser.validated(title: marker, artist: marker)
                    }
                    Button("Resume song") {
                        track = StreamTrackMetadataParser.validated(title: "Never Tear Us Apart", artist: "INXS")
                    }
                }
                Spacer()
            }
            .padding(metrics.horizontalGutter)
            .frame(maxWidth: metrics.playerMaximumWidth)
            .frame(maxWidth: .infinity)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .tint(.purple)
    }
}
#endif
