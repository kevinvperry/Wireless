import SwiftUI

@main
struct WirelessApp: App {
    @StateObject private var player = MobilePlayer.shared

    init() {
        // Install the notification delegate before launch completes so a Sleep
        // Schedule "Still Listening" tap that wakes the app is delivered.
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["WIRELESS_METADATA_PREVIEW"] == "1" {
                WirelessMetadataPreview()
            } else {
                WirelessRootView(player: player)
            }
            #else
            WirelessRootView(player: player)
            #endif
        }
        .defaultSize(width: 430, height: 860)
    }
}

private struct WirelessRootView: View {
    @ObservedObject var player: MobilePlayer
    @State private var showsLaunchAnimation = true

    var body: some View {
        ZStack {
            RadioPlayerView(player: player)
            if showsLaunchAnimation {
                WirelessLaunchView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.purple)
        .task { @MainActor in
            player.autoResumeIfEnabled()
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showsLaunchAnimation = false
            }
        }
    }
}

private struct WirelessLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatesScale = false
    @State private var tunesNeedle = false
    @State private var revealsCopy = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            let markSize = min(280 * metrics.contentScale, proxy.size.width - (metrics.horizontalGutter * 2), proxy.size.height * 0.42)
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                colors: [Color.purple.opacity(0.20), .clear],
                center: .center,
                startRadius: 12,
                endRadius: 290
            )
            .ignoresSafeArea()

            VStack(spacing: 20 * metrics.contentScale) {
                WirelessLaunchMark(animatesScale: animatesScale,
                                   tunesNeedle: tunesNeedle,
                                   reduceMotion: reduceMotion)
                    .frame(width: markSize, height: markSize)
                    .shadow(color: Color(red: 1, green: 0.35, blue: 0.29).opacity(0.18), radius: 28)

                Text("Wireless")
                    .font(.system(size: 30 * metrics.contentScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Fine Tuning Your Radio Presets")
                    .font(.system(size: 15 * metrics.contentScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, metrics.horizontalGutter)
            .opacity(revealsCopy ? 1 : 0)
            .scaleEffect(revealsCopy ? 1 : 0.92)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wireless. Fine Tuning Your Radio Presets")
        .task { @MainActor in
            if reduceMotion {
                animatesScale = true
                tunesNeedle = true
                revealsCopy = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { revealsCopy = true }
                withAnimation(.easeInOut(duration: 0.70)) { tunesNeedle = true }
                withAnimation(.easeInOut(duration: 0.38)) { animatesScale = true }
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.38)) { animatesScale = false }
            }
        }
    }
}

private struct WirelessLaunchMark: View {
    let animatesScale: Bool
    let tunesNeedle: Bool
    let reduceMotion: Bool

    private struct ScaleMark: Identifiable {
        let id: Int
        let x: CGFloat
        let height: CGFloat
        let strong: Bool
    }

    private let marks = [
        ScaleMark(id: 0, x: 22, height: 28, strong: true),
        ScaleMark(id: 1, x: 30, height: 12, strong: false),
        ScaleMark(id: 2, x: 38, height: 12, strong: false),
        ScaleMark(id: 3, x: 46, height: 12, strong: false),
        ScaleMark(id: 4, x: 54, height: 28, strong: true),
        ScaleMark(id: 5, x: 62, height: 12, strong: false),
        ScaleMark(id: 6, x: 70, height: 12, strong: false),
        ScaleMark(id: 7, x: 78, height: 12, strong: false),
        ScaleMark(id: 8, x: 86, height: 28, strong: true),
        ScaleMark(id: 9, x: 94, height: 12, strong: false),
        ScaleMark(id: 10, x: 102, height: 12, strong: false),
        ScaleMark(id: 11, x: 110, height: 12, strong: false),
        ScaleMark(id: 12, x: 118, height: 28, strong: true)
    ]

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 140
            ZStack {
                ForEach(marks) { mark in
                    Capsule()
                        .fill(Color(red: 0.957, green: 0.922, blue: 0.867)
                            .opacity(mark.strong ? 1 : 0.60))
                        .frame(width: (mark.strong ? 3 : 2) * unit,
                               height: mark.height * unit)
                        .scaleEffect(y: reduceMotion ? 1 : (animatesScale
                            ? (mark.id.isMultiple(of: 2) ? 1.15 : 0.82)
                            : (mark.id.isMultiple(of: 2) ? 0.88 : 1.12)))
                        .position(x: mark.x * unit, y: 70 * unit)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30 + Double(mark.id % 4) * 0.025)
                            .delay(Double(mark.id % 5) * 0.018), value: animatesScale)
                }

                Capsule()
                    .fill(Color(red: 1, green: 0.353, blue: 0.290))
                    .frame(width: 9 * unit, height: 96 * unit)
                    .position(x: (tunesNeedle ? 76.5 : 69.5) * unit, y: 70 * unit)
                    .scaleEffect(y: reduceMotion ? 1 : (tunesNeedle ? 1 : 0.90))
                    .shadow(color: Color(red: 1, green: 0.353, blue: 0.290).opacity(0.30), radius: 8)
            }
            .frame(width: 140 * unit, height: 140 * unit)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
