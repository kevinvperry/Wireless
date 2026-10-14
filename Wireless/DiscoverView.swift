import SwiftUI
import UIKit

struct DiscoverView: View {
    @ObservedObject var library: StationLibrary
    var currentID: String
    var isPlaying: Bool
    var favouritesOnly = false
    var play: (DirectoryStation) -> Void
    var browse: (() -> Void)? = nil
    var region: DiscoverRegion? = nil
    var networkFilter = ""
    var cityFilter = ""
    var stateFilter = ""
    @State private var query = ""

    private var showsSettingsButton: Bool {
        !favouritesOnly && region == nil && networkFilter.isEmpty && cityFilter.isEmpty && stateFilter.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search stations", text: $query).textFieldStyle(.plain)
                    .accessibilityIdentifier("stationSearch")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                Button { Task { await library.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("Refresh directory").disabled(library.isLoading)
            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal).padding(.top, 12)
            if !networkFilter.isEmpty || !cityFilter.isEmpty || !stateFilter.isEmpty { activeBrowseCard(metrics: metrics).padding(.horizontal).padding(.top, 12) }
            if library.isLoading { ProgressView("Refreshing directory…").font(.caption).padding(.bottom, 8) }
            if let error = library.error {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8).accessibilityIdentifier("directoryError")
            }
            let filtered = library.results(favouritesOnly: favouritesOnly, query: query, network: networkFilter, city: cityFilter, state: stateFilter)
            let results = region.map { DiscoverRegions.stations(filtered, in: $0) } ?? filtered
            if !favouritesOnly && region == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && networkFilter.isEmpty && cityFilter.isEmpty && stateFilter.isEmpty {
                regionTiles(metrics: metrics)
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label(favouritesOnly && library.favourites.isEmpty ? "No favourites yet" : "No stations found", systemImage: favouritesOnly ? "heart" : "magnifyingglass")
                } description: {
                    Text(favouritesOnly && library.favourites.isEmpty ? "Save a station for quick access here." : "Try another search or clear your filters.")
                } actions: {
                    if let browse, favouritesOnly { Button("Browse Stations", action: browse) }
                    else if !query.isEmpty { Button("Clear search") { query = "" } }
                }
            } else {
                List(results) { station in
                    HStack(spacing: metrics.rowSpacing) {
                        StationImage(station: station).frame(width: metrics.artwork, height: metrics.artwork)
                        Button { play(station) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(station.name).font(.system(size: metrics.primary, weight: .semibold)).foregroundStyle(.primary)
                                Text([station.network, station.location].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: metrics.secondary)).foregroundStyle(.secondary)
                                if !library.available(station) { Text("No longer in the directory").font(.system(size: metrics.secondary)).foregroundStyle(.secondary) }
                                else if station.preferredStream == nil { Text("No compatible stream available").font(.system(size: metrics.secondary)).foregroundStyle(.secondary) }
                                else if currentID == station.id { Label(isPlaying ? "Playing" : "Selected", systemImage: isPlaying ? "waveform" : "radio").font(.system(size: metrics.secondary)).foregroundStyle(.purple) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!library.available(station) || station.preferredStream == nil)
                            .accessibilityLabel("Play \(station.name)")
                        Button { library.toggle(station) } label: {
                            Image(systemName: library.contains(station) ? "heart.fill" : "heart").foregroundStyle(.purple).frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("\(library.contains(station) ? "Remove" : "Add") \(station.name) \(library.contains(station) ? "from" : "to") Favourites")
                    }.padding(.vertical, metrics.rowPadding)
                }.listStyle(.plain).scrollContentBackground(.hidden)
                Text("\(results.count) \(results.count == 1 ? "station" : "stations")").font(.caption).foregroundStyle(.secondary).padding(8)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.refresh() }
        .toolbar {
            if showsSettingsButton {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WirelessSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
            }
        }
    }

    private func regionTiles(metrics: WirelessLayoutMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Explore the directory").font(.system(size: metrics.detailTitle, weight: .bold)).padding(.horizontal, 2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 380), spacing: 14)], spacing: 14) {
                    NavigationLink(value: DiscoverBrowseRoute.networks) {
                        DiscoverBrowseTile(title: "Networks", subtitle: "Browse \(library.networks.count) networks", symbol: "dot.radiowaves.left.and.right", metrics: metrics, prominent: true)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseNetworks")
                    NavigationLink(value: DiscoverBrowseRoute.national) {
                        DiscoverBrowseTile(title: "National", subtitle: "Australia-wide stations", symbol: "antenna.radiowaves.left.and.right", metrics: metrics, prominent: true)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseNational")
                }
                Text("Browse by location").font(.system(size: metrics.detailTitle, weight: .bold)).padding(.horizontal, 2).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(DiscoverRegion.allCases) { region in
                        NavigationLink(value: region.rawValue) {
                            DiscoverBrowseTile(title: region.rawValue, symbol: region.symbol, metrics: metrics)
                        }.buttonStyle(.plain).accessibilityIdentifier("region-\(region.rawValue)")
                    }
                    NavigationLink(value: DiscoverBrowseRoute.locations) {
                        DiscoverBrowseTile(title: "Other Locations", subtitle: "Find towns and regional stations", symbol: "map", metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseLocations")
                }
                Text("Browse by State").font(.system(size: metrics.detailTitle, weight: .bold)).padding(.horizontal, 2).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(AustralianBroadcastState.allCases) { state in
                        NavigationLink(value: DiscoverBrowseRoute.state(state.rawValue)) {
                            DiscoverBrowseTile(title: state.shortTitle, symbol: "map.fill", metrics: metrics)
                        }.buttonStyle(.plain).accessibilityIdentifier("state-\(state.rawValue)")
                    }
                }
            }.padding(18).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("regionTiles")
    }

    private func activeBrowseCard(metrics: WirelessLayoutMetrics) -> some View {
        HStack(spacing: 12) {
            Image(systemName: !networkFilter.isEmpty ? "dot.radiowaves.left.and.right" : (!stateFilter.isEmpty ? "map.fill" : "mappin.and.ellipse"))
                .font(.system(size: metrics.primary, weight: .semibold)).foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(!networkFilter.isEmpty ? "Network" : (!stateFilter.isEmpty ? "State / coverage" : "Location")).font(.caption).foregroundStyle(.secondary)
                Text(!networkFilter.isEmpty ? networkFilter : (!stateFilter.isEmpty ? stateFilter : cityFilter)).font(.system(size: metrics.primary, weight: .semibold))
            }
            Spacer()
        }.padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct WirelessSettingsView: View {
    @AppStorage("keepScreenAwakeDuringPlayback") private var keepScreenAwake = false
    @AppStorage(MobilePlayer.autoResumeKey) private var autoResume = false
    @State private var developerTapCount = 0
    @State private var diagnosticsUnlocked = false
    private let testFlightURL = URL(string: "https://testflight.apple.com/join/DnX2AkYf")!

    private var cardBackground: Color {
        if #available(iOS 26, *) { return Color.white.opacity(0.05) }
        return Color.white.opacity(0.08)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoResume) {
                    settingsRow("Auto Resume", systemImage: "play.circle")
                }
                .accessibilityIdentifier("autoResume")
                Toggle(isOn: $keepScreenAwake) {
                    settingsRow("Keep Screen Awake", systemImage: "sun.max")
                }
                .accessibilityIdentifier("keepScreenAwake")
            } header: {
                Text("Playback")
            } footer: {
                Text("Auto Resume starts playing your last station when Wireless opens. Keep Screen Awake stops the screen dimming while a station is playing on the full-screen player. Both are off by default.")
            }
            .listRowBackground(cardBackground)

            Section {
                NavigationLink {
                    WirelessSupportView()
                } label: {
                    settingsRow("Wireless Support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("wirelessSupport")
            } header: {
                Text("Support")
            } footer: {
                Text("Learn how to discover stations, use TV Sync and improve playback reliability.")
            }
            .listRowBackground(cardBackground)

            if diagnosticsUnlocked {
                Section {
                    NavigationLink {
                        StreamDiagnosticView()
                    } label: {
                        settingsRow("Stream Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("streamDiagnostics")
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Use this hidden log while investigating stream reliability or TV Sync performance.")
                }
                .listRowBackground(cardBackground)
            }

            Section {
                ShareLink(
                    item: testFlightURL,
                    subject: Text("Try Wireless on TestFlight"),
                    message: Text("Try Wireless – Fine Tuning Your Radio Presets")
                ) {
                    HStack {
                        settingsRow("Share TestFlight link with your friends", systemImage: "square.and.arrow.up")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Opens the system share sheet with the Wireless TestFlight link")
                .accessibilityIdentifier("shareTestFlight")
            } header: {
                Text("Share Wireless")
            } footer: {
                Text("Invite friends to install the current Wireless beta through Apple TestFlight.")
            }
            .listRowBackground(cardBackground)

            Section {
                Link(destination: URL(string: "https://github.com/kevinvperry/Wireless")!) {
                    settingsRow("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityHint("Opens the public Wireless source repository in your browser")
                .accessibilityIdentifier("wirelessSourceCode")
                Link(destination: URL(string: "https://github.com/kevinvperry/Wireless/blob/main/LICENSE")!) {
                    settingsRow("MIT Licence", systemImage: "doc.text")
                }
                .accessibilityHint("Opens the MIT licence for Wireless's original code and documentation")
                .accessibilityIdentifier("wirelessMITLicence")
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    settingsRow("Open Source Acknowledgements", systemImage: "doc.plaintext")
                }
                .accessibilityIdentifier("acknowledgements")
                HStack {
                    settingsRow("Version", systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(diagnosticsUnlocked ? .purple : .secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    developerTapCount += 1
                    if developerTapCount >= 5 {
                        diagnosticsUnlocked = true
                        developerTapCount = 0
                    }
                }
                .accessibilityIdentifier("versionRow")
            } header: {
                Text("About")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wireless is open source. Its original code and documentation use the MIT Licence. Vocal Boost retains MPL-2.0; see Open Source Acknowledgements for details.")
                        .accessibilityIdentifier("wirelessLicenceSummary")
                    if diagnosticsUnlocked { Text("Developer tools unlocked.").foregroundStyle(.purple) }
                }
            }
            .listRowBackground(cardBackground)
        }
        .listSectionSpacing(WirelessLayoutMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.purple)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private func settingsRow(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.purple).frame(width: 24)
        }
    }
}

enum DiscoverBrowseRoute {
    static let networks = "DiscoverNetworks"
    static let locations = "DiscoverLocations"
    static let national = "DiscoverNational"
    private static let networkPrefix = "DiscoverNetwork:"
    private static let locationPrefix = "DiscoverLocation:"
    private static let statePrefix = "DiscoverState:"

    static func network(_ value: String) -> String { networkPrefix + value }
    static func location(_ value: String) -> String { locationPrefix + value }
    static func state(_ value: String) -> String { statePrefix + value }
    static func networkValue(_ route: String) -> String? { route.hasPrefix(networkPrefix) ? String(route.dropFirst(networkPrefix.count)) : nil }
    static func locationValue(_ route: String) -> String? { route.hasPrefix(locationPrefix) ? String(route.dropFirst(locationPrefix.count)) : nil }
    static func stateValue(_ route: String) -> String? { route.hasPrefix(statePrefix) ? String(route.dropFirst(statePrefix.count)) : nil }
}

struct DiscoverFacetView: View {
    enum Kind: Equatable { case networks, locations }
    @ObservedObject var library: StationLibrary
    let kind: Kind
    @State private var query = ""

    private var values: [String] {
        let source = kind == .networks ? library.networks : library.cities.filter { city in
            !DiscoverRegion.allCases.contains { $0.rawValue.caseInsensitiveCompare(city) == .orderedSame }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source : source.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 320), spacing: 14)], spacing: 14) {
                    ForEach(values, id: \.self) { value in
                        NavigationLink(value: kind == .networks ? DiscoverBrowseRoute.network(value) : DiscoverBrowseRoute.location(value)) {
                            DiscoverBrowseTile(title: value, subtitle: stationCountText(value), symbol: kind == .networks ? "dot.radiowaves.left.and.right" : "mappin.and.ellipse", metrics: metrics)
                        }.buttonStyle(.plain).accessibilityIdentifier("browse-\(kind == .networks ? "network" : "location")-\(value)")
                    }
                }.padding(18).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
            .searchable(text: $query, prompt: kind == .networks ? "Search networks" : "Search towns and locations")
            .overlay { if values.isEmpty { ContentUnavailableView.search(text: query) } }
        }
        .task { await library.refresh() }
    }

    private func stationCountText(_ value: String) -> String {
        let count = kind == .networks
            ? library.results(favouritesOnly: false, query: "", network: value, city: "").count
            : library.results(favouritesOnly: false, query: "", network: "", city: value).count
        return "\(count) \(count == 1 ? "station" : "stations")"
    }
}

struct DiscoverBrowseTile: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let metrics: WirelessLayoutMetrics
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).font(.system(size: metrics.detailTitle, weight: .semibold)).foregroundStyle(.purple)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(title).font(.system(size: metrics.primary, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            if let subtitle { Text(subtitle).font(.system(size: metrics.secondary)).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: prominent ? 116 : 98, alignment: .leading)
        .padding(18)
        .background(LinearGradient(colors: [Color.purple.opacity(prominent ? 0.34 : 0.23), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.purple.opacity(prominent ? 0.35 : 0.18), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct StationImage: View {
    let station: DirectoryStation
    var cornerRadius: CGFloat = 10
    var isDecorative = true
    var body: some View {
        ZStack {
            if let url = URL(string: station.logo_url), url.scheme == "https" {
                FlattenedStationArtwork(url: url, fallback: AnyView(fallback))
            } else {
                Color.purple.opacity(0.15)
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(isDecorative)
    }
    private var fallback: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(geometry.size.width > 100 ? .largeTitle : .title2).foregroundStyle(.purple)
                if geometry.size.width > 100 { Text(station.name).font(.title2.bold()).multilineTextAlignment(.center).padding(.horizontal, 12) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FlattenedStationArtwork: View {
    let url: URL
    let fallback: AnyView
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                fallback
            }
        }
        .task(id: url) {
            image = nil
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let source = UIImage(data: data),
                      source.size.width > 0, source.size.height > 0 else { return }
                image = Self.flattened(source)
            } catch is CancellationError { }
            catch { }
        }
    }

    private static func flattened(_ source: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = source.scale
        return UIGraphicsImageRenderer(size: source.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: source.size))
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }
    }
}
