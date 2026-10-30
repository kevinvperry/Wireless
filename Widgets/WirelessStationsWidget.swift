import SwiftUI
import WidgetKit
import UIKit

struct StationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var artwork: [String: Data] = [:]

    static var preview: StationEntry {
        let stations = ["Wireless Radio Melbourne", "The Commute with Marty Sheargold", "Melbourne Music", "Sport Live", "Classic Radio", "National News Radio", "Community Radio"].enumerated().map {
            WidgetDisplayStation(id: "preview-\($0.offset)", name: $0.element,
                                 subtitle: "Live radio", thumbnailFilename: nil)
        }
        return StationEntry(date: Date(), snapshot: WidgetSnapshot(schemaVersion: 1, generatedAt: Date(),
            current: stations[0], favourites: Array(stations.dropFirst()), isPlaying: false))
    }
}

struct StationProvider: TimelineProvider {
    func placeholder(in context: Context) -> StationEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (StationEntry) -> Void) {
        completion(context.isPreview ? .preview : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StationEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(900))))
    }
    private func entry() -> StationEntry {
        let storage = WidgetSharedStorage()
        let snapshot = try? storage.read()
        var artwork: [String: Data] = [:]
        for station in ([snapshot?.current].compactMap { $0 } + (snapshot?.favourites ?? [])) {
            if let filename = station.thumbnailFilename,
               let url = try? storage.thumbnailURL(filename: filename),
               let data = try? Data(contentsOf: url), data.count <= WidgetSharedConfiguration.maximumThumbnailBytes {
                artwork[filename] = data
            }
        }
        return StationEntry(date: Date(), snapshot: snapshot, artwork: artwork)
    }
}

struct WirelessStationsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConfiguration.widgetKind, provider: StationProvider()) {
            StationWidgetView(entry: $0)
                .containerBackground(for: .widget) {
                    WirelessWidgetContainerBackground()
                }
        }
        .configurationDisplayName("Wireless Stations")
        .description("Control your selected station and your highest-ranked favourites.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StationWidgetView: View {
    @Environment(\.widgetFamily) private var hostFamily
    let entry: StationEntry
    private let previewFamily: WidgetFamily?
    private var family: WidgetFamily { previewFamily ?? hostFamily }

    init(entry: StationEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = family
    }
    private var primary: WidgetDisplayStation? { entry.snapshot?.primary }
    private var accessory: Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    var body: some View {
        Group {
            if family == .accessoryInline {
                // WidgetKit's inline family supports navigation, not playback buttons.
                Text(primary.map { "Wireless · \($0.name)" } ?? "Open Wireless to choose a station")
            } else if let primary {
                switch family {
                case .accessoryCircular:
                    VStack(spacing: 2) {
                        control(primary, size: 32)
                        Text(primary.name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    }
                case .accessoryRectangular:
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wireless").font(.caption2).widgetAccentable()
                            Text(primary.name).font(.caption.weight(.semibold)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        control(primary, size: 32)
                    }
                case .systemSmall:
                    GeometryReader { geometry in
                        smallContent(primary, height: geometry.size.height)
                    }
                case .systemMedium:
                    GeometryReader { geometry in
                        mediumContent(primary, height: geometry.size.height)
                    }
                case .systemExtraLarge:
                    GeometryReader { geometry in
                        extraLargeContent(primary, height: geometry.size.height)
                    }
                default:
                    GeometryReader { geometry in
                        largeContent(primary, height: geometry.size.height)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Wireless", systemImage: "radio").font(.headline)
                    if family != .accessoryCircular {
                        Text("Open Wireless and choose a station or add favourites.")
                            .font(.caption).foregroundStyle(accessory ? Color.secondary : Color.white.opacity(0.64))
                    }
                }
            }
        }
        .foregroundStyle(accessory ? Color.primary : .white)
    }

    private let metadataColour = Color.white.opacity(0.64)

    private func state(_ station: WidgetDisplayStation) -> String {
        guard station.id == entry.snapshot?.current?.id else { return "Favourite" }
        return entry.snapshot?.isPlaying == true ? "Live radio" : "Ready to play"
    }

    private var statusHeading: String {
        entry.snapshot?.isPlaying == true ? "NOW PLAYING" : "READY TO PLAY"
    }

    private var following: [WidgetDisplayStation] { entry.snapshot?.following ?? [] }

    private var favouritesHeading: some View {
        Label("Favourites", systemImage: "heart.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5)
    }

    private func heading() -> some View {
        Text(statusHeading)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.purple)
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func smallContent(_ station: WidgetDisplayStation, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            artwork(station, size: max(48, min(80, height - 66)))
                .frame(maxWidth: .infinity)
            Text(station.name)
                .font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text(entry.snapshot?.isPlaying == true ? "LIVE RADIO" : "READY")
                    .font(.caption2.weight(.bold)).foregroundStyle(.purple).widgetAccentable()
                Spacer(minLength: 2)
                control(station, size: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func mediumContent(_ station: WidgetDisplayStation, height: CGFloat) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .bottom) {
                    artwork(station, size: max(48, min(72, height - 64)))
                    Spacer(minLength: 3)
                    control(station, size: 27)
                }
                heading()
                Text(station.name).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 10) {
                favouritesHeading
                ForEach(Array(following.prefix(2))) { favourite in
                    stationRow(favourite, artworkSize: 32, controlSize: 25, compact: true)
                }
                if following.isEmpty { emptyFavourites }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func primaryHeader(_ station: WidgetDisplayStation, artworkSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            artwork(station, size: artworkSize)
            VStack(alignment: .leading, spacing: 4) {
                heading()
                Text(station.name).font(.headline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !station.subtitle.isEmpty {
                    Text(station.subtitle).font(.caption).foregroundStyle(metadataColour).lineLimit(1)
                }
                Text(state(station)).font(.caption2).foregroundStyle(metadataColour).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control(station, size: 40)
        }
    }

    private func largeContent(_ station: WidgetDisplayStation, height: CGFloat) -> some View {
        let artworkSize = max(76, min(104, height * 0.29))
        let rowSize = max(32, min(52, (height - artworkSize - 54) / 4 - 4))
        return VStack(alignment: .leading, spacing: 8) {
            primaryHeader(station, artworkSize: artworkSize)
            separator
            favouritesHeading
            if following.isEmpty {
                emptyFavourites.frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(following.prefix(4))) { favourite in
                        stationRow(favourite, artworkSize: rowSize, controlSize: 28)
                            .frame(maxHeight: .infinity)
                    }
                }.frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func extraLargeContent(_ station: WidgetDisplayStation, height: CGFloat) -> some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                artwork(station, size: max(100, min(152, height * 0.47)))
                    .frame(maxWidth: .infinity)
                heading()
                Text(station.name).font(.title3.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                if !station.subtitle.isEmpty {
                    Text(station.subtitle).font(.caption).foregroundStyle(metadataColour).lineLimit(1)
                }
                HStack {
                    Text(state(station)).font(.caption).foregroundStyle(metadataColour)
                    Spacer(minLength: 4)
                    control(station, size: 40)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 12) {
                favouritesHeading
                if following.isEmpty { emptyFavourites }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(following.prefix(6))) { favourite in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { artwork(favourite, size: 44); Spacer(minLength: 3); control(favourite, size: 28) }
                            Text(favourite.name).font(.caption.weight(.semibold))
                                .foregroundStyle(.white).lineLimit(2)
                        }
                    }
                }.frame(maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyFavourites: some View {
        Text("Add favourites in Wireless").font(.caption).foregroundStyle(metadataColour)
    }

    private func stationRow(_ station: WidgetDisplayStation, artworkSize: CGFloat,
                            controlSize: CGFloat, compact: Bool = false) -> some View {
        HStack(spacing: compact ? 6 : 9) {
            artwork(station, size: artworkSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(station.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 1)
                if !compact, !station.subtitle.isEmpty {
                    Text(station.subtitle).font(.caption2).foregroundStyle(metadataColour).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control(station, size: controlSize)
        }
    }

    private func artwork(_ station: WidgetDisplayStation, size: CGFloat) -> some View {
        Group {
            if let filename = station.thumbnailFilename, let data = entry.artwork[filename],
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().background(.white)
            } else {
                Color.purple.opacity(0.3).overlay { Image(systemName: "radio").foregroundStyle(.white) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }

    private func control(_ station: WidgetDisplayStation, size: CGFloat) -> some View {
        let playing = station.id == entry.snapshot?.current?.id && entry.snapshot?.isPlaying == true
        return Button(intent: StationPlaybackIntent(stationID: station.id, shouldPlay: !playing)) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .modifier(WirelessWidgetPlaybackSurface(isAccessory: accessory))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(playing ? "Pause" : "Play") \(station.name)")
        .widgetAccentable()
    }
}

private struct WirelessWidgetContainerBackground: View {
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            WirelessWidgetCharcoalGlassBackground()
        default:
            Color.clear
        }
    }
}

/// AI CONTEXT — Widget wallpaper varies, so Material alone cannot guarantee
/// contrast. This surface begins with opaque charcoal, then layers restrained
/// depth and glass above it. The result looks translucent without allowing
/// arbitrary wallpaper colours to compromise text legibility.
struct WirelessWidgetCharcoalGlassBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.047, blue: 0.054)

            LinearGradient(
                colors: [
                    Color(red: 0.145, green: 0.15, blue: 0.17),
                    Color(red: 0.065, green: 0.067, blue: 0.077),
                    Color(red: 0.105, green: 0.088, blue: 0.115)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.88)

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.17),
                    Color.purple.opacity(0.035),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )

            WirelessWidgetCharcoalTexture()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.015),
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.screen)

            nativeGlassSheen

            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.055),
                            Color.purple.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    @ViewBuilder
    private var nativeGlassSheen: some View {
        if #available(iOSApplicationExtension 26.0, *) {
            Color.white.opacity(0.018)
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.035)),
                    in: ContainerRelativeShape()
                )
        } else {
            Color.white.opacity(0.015)
        }
    }
}

/// AI CONTEXT — Fixed modular coordinates provide subtle fibre/grain without
/// randomness, image assets, animation, or persistent state. Keep this bounded
/// and faint so texture never competes with artwork or episode metadata.
private struct WirelessWidgetCharcoalTexture: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<72 {
                let xUnit = CGFloat((index * 47 + 13) % 101) / 100
                let yUnit = CGFloat((index * 83 + 29) % 103) / 102
                let diameter = CGFloat(1 + (index % 3)) * 0.55
                let rect = CGRect(
                    x: xUnit * size.width,
                    y: yUnit * size.height,
                    width: diameter,
                    height: diameter
                )
                let colour = index.isMultiple(of: 4)
                    ? Color.black.opacity(0.22)
                    : Color.white.opacity(0.12)
                context.fill(Path(ellipseIn: rect), with: .color(colour))
            }

            for index in 0..<14 {
                let yUnit = CGFloat((index * 31 + 7) % 97) / 96
                var path = Path()
                path.move(to: CGPoint(x: 0, y: yUnit * size.height))
                path.addLine(
                    to: CGPoint(
                        x: size.width,
                        y: min(size.height, yUnit * size.height + 0.7)
                    )
                )
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.025)),
                    lineWidth: 0.45
                )
            }
        }
        .blendMode(.softLight)
        .opacity(0.7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


// Autohop uses a deterministic glass-style control surface: native glass on
// intent labels can disappear when WidgetKit extracts the interactive layer.
private struct WirelessWidgetPlaybackSurface: ViewModifier {
    var isAccessory = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAccessory {
            content
        } else {
            glassSurface(content)
        }
    }

    private func glassSurface(_ content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.10, blue: 0.96),
                        Color(red: 0.62, green: 0.08, blue: 0.76)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.purple.opacity(0.24), radius: 3, y: 1)
    }
}

#Preview("Small", as: .systemSmall) { WirelessStationsWidget() } timeline: { StationEntry.preview }
#Preview("Medium", as: .systemMedium) { WirelessStationsWidget() } timeline: { StationEntry.preview }
#Preview("Large", as: .systemLarge) { WirelessStationsWidget() } timeline: { StationEntry.preview }
#Preview("Lock Screen", as: .accessoryRectangular) { WirelessStationsWidget() } timeline: { StationEntry.preview }
