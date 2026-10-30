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
    var subnetworkFilter = ""
    var cityFilter = ""
    var stateFilter = ""
    var musicGenreFilter = ""
    var tripleJGroupFilter: TripleJBrowseGroup? = nil
    @State private var query = ""
    @State private var pendingRemoval: DirectoryStation?

    private var showsSettingsButton: Bool {
        !favouritesOnly && region == nil && networkFilter.isEmpty && subnetworkFilter.isEmpty && cityFilter.isEmpty && stateFilter.isEmpty && musicGenreFilter.isEmpty
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
            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: metrics.listMaximumWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.pagePadding).padding(.top, 12)
            if !networkFilter.isEmpty || !subnetworkFilter.isEmpty || !cityFilter.isEmpty || !stateFilter.isEmpty || !musicGenreFilter.isEmpty { activeBrowseCard(metrics: metrics).padding(.horizontal).padding(.top, 12) }
            if library.isLoading { ProgressView("Refreshing directory…").font(.caption).padding(.bottom, 8) }
            if let error = library.error {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8).accessibilityIdentifier("directoryError")
            }
            let filtered = library.results(favouritesOnly: favouritesOnly, query: query, network: networkFilter, city: cityFilter, state: stateFilter, subnetwork: subnetworkFilter, musicGenre: musicGenreFilter)
            let grouped = tripleJGroupFilter.map { group in filtered.filter(group.includes) } ?? filtered
            let results = region.map { DiscoverRegions.stations(grouped, in: $0) } ?? grouped
            if !favouritesOnly && region == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && networkFilter.isEmpty && subnetworkFilter.isEmpty && cityFilter.isEmpty && stateFilter.isEmpty && musicGenreFilter.isEmpty {
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
                let ratingsCity = region?.rawValue ?? cityFilter
                let isRatingsList = ["Sydney", "Melbourne", "Brisbane", "Adelaide", "Perth"].contains(ratingsCity)
                    && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let topRatingStations = isRatingsList ? StationListOrganisation.topRatingStations(for: ratingsCity, from: results) : []
                let alphabeticalStations = isRatingsList ? StationListOrganisation.excludingTopRatings(for: ratingsCity, from: results) : results
                let alphabeticalSections = StationListOrganisation.alphabeticalSections(from: alphabeticalStations)
                List {
                    if favouritesOnly {
                        ForEach(results) { station in stationRow(station, metrics: metrics) }
                    } else {
                        if !topRatingStations.isEmpty {
                            Section("Top Rating Stations") {
                                ForEach(topRatingStations) { station in stationRow(station, metrics: metrics) }
                            }
                        }
                        ForEach(alphabeticalSections) { section in
                            Section {
                                ForEach(section.stations) { station in stationRow(station, metrics: metrics) }
                            } header: {
                                Text(section.title)
                            }
                            .sectionIndexLabel(section.title)
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .listSectionIndexVisibility(favouritesOnly ? .hidden : .visible)
                    .contentMargins(.bottom, metrics.stationListBottomClearance, for: .scrollContent)
                    .frame(maxWidth: metrics.listMaximumWidth)
                    .frame(maxWidth: .infinity)
                Text("\(results.count) \(results.count == 1 ? "station" : "stations")").font(.caption).foregroundStyle(.secondary).padding(8)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await library.refresh() }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this station") from Favourites?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Favourites", role: .destructive) {
                if let station = pendingRemoval, library.contains(station) {
                    library.toggle(station)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You can add this station again from Discover.")
        }
        .toolbar {
            if showsSettingsButton {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WirelessSettingsView(player: .shared)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: DirectoryStation, metrics: WirelessLayoutMetrics) -> some View {
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
            Button {
                if library.contains(station) { pendingRemoval = station }
                else { library.toggle(station) }
            } label: {
                Image(systemName: library.contains(station) ? "heart.fill" : "heart").foregroundStyle(.purple).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("\(library.contains(station) ? "Remove" : "Add") \(station.name) \(library.contains(station) ? "from" : "to") Favourites")
        }.padding(.vertical, metrics.rowPadding)
    }

    private func regionTiles(metrics: WirelessLayoutMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.discoverSectionSpacing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Find your station")
                        .font(.system(size: metrics.discoverHeading, weight: .bold, design: .rounded))
                    Text("Explore Australian radio by broadcaster, place or what you want to hear.")
                        .font(.system(size: metrics.secondary))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: metrics.tileSpacing) {
                    NavigationLink(value: DiscoverBrowseRoute.networks) {
                        DiscoverQuickBrowseTile(title: "Networks", subtitle: "Browse broadcasters", symbol: "dot.radiowaves.left.and.right", metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseNetworks")
                    NavigationLink(value: DiscoverBrowseRoute.locations) {
                        DiscoverQuickBrowseTile(title: "Locations", subtitle: "Cities, states & regions", symbol: "australia.outline", metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseLocations")
                }

                Text("Browse by interest")
                    .font(.system(size: metrics.discoverSectionTitle, weight: .bold, design: .rounded))
                    .padding(.horizontal, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: metrics.tileSpacing) {
                    NavigationLink(value: DiscoverBrowseRoute.genres) {
                        DiscoverInterestTile(title: "Music", subtitle: "Genres for every mood", symbol: "music.note", palette: .music, metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseGenres")
                    NavigationLink(value: DiscoverBrowseRoute.genre("News")) {
                        DiscoverInterestTile(title: "News and Talkback", subtitle: "News, current affairs and conversation", symbol: "bubble.left.and.text.bubble.right", palette: .news, metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseNews")
                    NavigationLink(value: DiscoverBrowseRoute.genre("Sport")) {
                        DiscoverInterestTile(title: "Sport", subtitle: "Commentary, analysis and racing", symbol: "sportscourt", palette: .sport, metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseSport")
                    NavigationLink(value: DiscoverBrowseRoute.network(NetworkBrowseOrdering.specialist)) {
                        DiscoverInterestTile(title: "Community & Specialist", subtitle: "Local voices and specialist services", symbol: "person.3.fill", palette: .community, metrics: metrics)
                    }.buttonStyle(.plain).accessibilityIdentifier("browseCommunitySpecialist")
                }
            }
            .padding(metrics.pagePadding)
            .padding(.bottom, metrics.discoverTileBottomClearance)
            .frame(maxWidth: metrics.playerMaximumWidth)
            .frame(maxWidth: .infinity)
        }.accessibilityIdentifier("regionTiles")
    }

    private func activeBrowseCard(metrics: WirelessLayoutMetrics) -> some View {
        HStack(spacing: 12) {
            Image(systemName: !musicGenreFilter.isEmpty ? "music.note.list" : !subnetworkFilter.isEmpty ? "square.grid.2x2" : (!networkFilter.isEmpty ? "dot.radiowaves.left.and.right" : (!stateFilter.isEmpty ? "map.fill" : "mappin.and.ellipse")))
                .font(.system(size: metrics.primary, weight: .semibold)).foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(!musicGenreFilter.isEmpty ? "Genre" : !subnetworkFilter.isEmpty ? "Sub-network" : (!networkFilter.isEmpty ? "Network" : (!stateFilter.isEmpty ? "State / coverage" : "Location"))).font(.caption).foregroundStyle(.secondary)
                Text(!musicGenreFilter.isEmpty ? musicGenreFilter : !subnetworkFilter.isEmpty ? subnetworkFilter : (!networkFilter.isEmpty ? networkFilter : (!stateFilter.isEmpty ? stateFilter : cityFilter))).font(.system(size: metrics.primary, weight: .semibold))
            }
            Spacer()
        }.padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DiscoverQuickBrowseTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let metrics: WirelessLayoutMetrics

    var body: some View {
        HStack(spacing: metrics.tileSpacing) {
            quickBrowseIcon
                .frame(width: metrics.discoverQuickIconFrame, height: metrics.discoverQuickIconFrame)
                .background(.purple.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .purple.opacity(0.3), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: metrics.primary, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: metrics.secondary)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.discoverQuickTileHeight, alignment: .leading)
        .padding(.horizontal, metrics.tileSpacing)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var quickBrowseIcon: some View {
        if symbol == "australia.outline" {
            AustraliaOutlineShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(8)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: metrics.discoverQuickIcon, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct AustraliaOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Simplified from Natural Earth's public-domain 1:110m Australian
        // coastline. Normalised here so the outline remains crisp at icon size.
        let mainland: [CGPoint] = [
            .init(x: 0.335, y: 0.638), .init(x: 0.279, y: 0.682), .init(x: 0.195, y: 0.685),
            .init(x: 0.153, y: 0.713), .init(x: 0.085, y: 0.690), .init(x: 0.103, y: 0.638),
            .init(x: 0.048, y: 0.477), .init(x: 0.068, y: 0.481), .init(x: 0.049, y: 0.431),
            .init(x: 0.057, y: 0.380), .init(x: 0.123, y: 0.333), .init(x: 0.216, y: 0.306),
            .init(x: 0.265, y: 0.220), .init(x: 0.284, y: 0.237), .init(x: 0.276, y: 0.225),
            .init(x: 0.325, y: 0.162), .init(x: 0.356, y: 0.151), .init(x: 0.413, y: 0.182),
            .init(x: 0.435, y: 0.117), .init(x: 0.479, y: 0.106), .init(x: 0.462, y: 0.084),
            .init(x: 0.474, y: 0.080), .init(x: 0.540, y: 0.110), .init(x: 0.567, y: 0.099),
            .init(x: 0.577, y: 0.112), .init(x: 0.545, y: 0.182), .init(x: 0.651, y: 0.254),
            .init(x: 0.674, y: 0.219), .init(x: 0.702, y: 0.068), .init(x: 0.734, y: 0.170),
            .init(x: 0.766, y: 0.182), .init(x: 0.789, y: 0.287), .init(x: 0.844, y: 0.325),
            .init(x: 0.863, y: 0.377), .init(x: 0.887, y: 0.378), .init(x: 0.934, y: 0.454),
            .init(x: 0.950, y: 0.529), .init(x: 0.935, y: 0.623), .init(x: 0.870, y: 0.776),
            .init(x: 0.788, y: 0.819), .init(x: 0.759, y: 0.788), .init(x: 0.727, y: 0.813),
            .init(x: 0.660, y: 0.792), .init(x: 0.636, y: 0.742), .init(x: 0.604, y: 0.728),
            .init(x: 0.606, y: 0.695), .init(x: 0.575, y: 0.719), .init(x: 0.597, y: 0.656),
            .init(x: 0.556, y: 0.709), .init(x: 0.517, y: 0.649), .init(x: 0.451, y: 0.619)
        ]
        let tasmania: [CGPoint] = [
            .init(x: 0.752, y: 0.863), .init(x: 0.789, y: 0.874), .init(x: 0.818, y: 0.866),
            .init(x: 0.832, y: 0.867), .init(x: 0.833, y: 0.899), .init(x: 0.823, y: 0.929),
            .init(x: 0.816, y: 0.922), .init(x: 0.800, y: 0.940), .init(x: 0.782, y: 0.938)
        ]

        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + value.x * rect.width, y: rect.minY + value.y * rect.height)
        }

        var path = Path()
        for ring in [mainland, tasmania] {
            guard let first = ring.first else { continue }
            path.move(to: point(first))
            for value in ring.dropFirst() { path.addLine(to: point(value)) }
            path.closeSubpath()
        }
        return path
    }
}

private struct DiscoverInterestTile: View {
    enum Palette {
        case music, news, sport, community

        var colours: [Color] {
            switch self {
            case .music: [.purple.opacity(0.95), .indigo.opacity(0.68)]
            case .news: [.blue.opacity(0.88), .indigo.opacity(0.62)]
            case .sport: [.orange.opacity(0.9), .red.opacity(0.64)]
            case .community: [.mint.opacity(0.8), .teal.opacity(0.6)]
            }
        }
    }

    let title: String
    let subtitle: String
    let symbol: String
    let palette: Palette
    let metrics: WirelessLayoutMetrics

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: palette.colours, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: metrics.discoverWatermark, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-8))
                .offset(x: metrics.tileSpacing, y: -metrics.tileSpacing / 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.discoverInterestIcon, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: metrics.discoverInterestIconFrame, height: metrics.discoverInterestIconFrame)
                        .background(.black.opacity(0.14), in: Circle())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: metrics.primary, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: metrics.secondary))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
            }
            .padding(metrics.discoverTilePadding)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.discoverInterestTileHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: palette.colours[0].opacity(0.2), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct WirelessSettingsView: View {
    @ObservedObject var player: MobilePlayer
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
                NavigationLink {
                    WirelessStatsView(store: .shared)
                } label: {
                    settingsRow("Listening Stats", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("listeningStats")

                NavigationLink {
                    WirelessListeningHistoryView(store: player.statsStore, player: player)
                } label: {
                    settingsRow("Listening History", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("listeningHistory")
            } header: {
                Text("Listening")
            } footer: {
                Text("See your listening time, top stations, patterns and individual listening sessions. Stats and history stay private on this device.")
            }
            .listRowBackground(cardBackground)

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
                    ShazamHistoryView(history: player.shazamHistory)
                } label: {
                    settingsRow("Shazam History", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("shazamHistory")
            } header: { Text("Music discovery") }
            footer: { Text("Revisit songs identified in Wireless. History is saved on this device.") }
            .listRowBackground(cardBackground)

            Section {
                NavigationLink {
                    WirelessSupportView()
                } label: {
                    settingsRow("Wireless Support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("wirelessSupport")

                Link(destination: WirelessContact.generalURL) {
                    HStack {
                        settingsRow("Contact Wireless", systemImage: "envelope")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Opens the Wireless contact form in your browser")
                .accessibilityIdentifier("contactWireless")
            } header: {
                Text("Support")
            } footer: {
                Text("Read the guide or contact Wireless about a technical, directory, ownership or legal concern.")
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
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
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
    static let genres = "DiscoverGenres"
    private static let genrePrefix = "DiscoverGenre:"
    static func genre(_ value: String) -> String { genrePrefix + value }
    static func genreValue(_ route: String) -> String? { route.hasPrefix(genrePrefix) ? String(route.dropFirst(genrePrefix.count)) : nil }
    static let networks = "DiscoverNetworks"
    static let locations = "DiscoverLocations"
    static let otherLocations = "DiscoverOtherLocations"
    static let national = "DiscoverNational"
    private static let networkPrefix = "DiscoverNetwork:"
    private static let locationPrefix = "DiscoverLocation:"
    private static let statePrefix = "DiscoverState:"
    private static let subnetworkPrefix = "DiscoverSubnetwork:"
    static let tripleJ = "DiscoverTripleJ"
    private static let tripleJGroupPrefix = "DiscoverTripleJGroup:"

    static func network(_ value: String) -> String { networkPrefix + value }
    static func location(_ value: String) -> String { locationPrefix + value }
    static func state(_ value: String) -> String { statePrefix + value }
    static func subnetwork(network: String, value: String) -> String { subnetworkPrefix + network + "|" + value }
    static func tripleJGroup(_ group: TripleJBrowseGroup) -> String { tripleJGroupPrefix + group.rawValue }
    static func networkValue(_ route: String) -> String? { route.hasPrefix(networkPrefix) ? String(route.dropFirst(networkPrefix.count)) : nil }
    static func locationValue(_ route: String) -> String? { route.hasPrefix(locationPrefix) ? String(route.dropFirst(locationPrefix.count)) : nil }
    static func stateValue(_ route: String) -> String? { route.hasPrefix(statePrefix) ? String(route.dropFirst(statePrefix.count)) : nil }
    static func subnetworkValue(_ route: String) -> (network: String, value: String)? {
        guard route.hasPrefix(subnetworkPrefix) else { return nil }
        let components = route.dropFirst(subnetworkPrefix.count).split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        return (components[0], components[1])
    }
    static func tripleJGroupValue(_ route: String) -> TripleJBrowseGroup? {
        guard route.hasPrefix(tripleJGroupPrefix) else { return nil }
        return TripleJBrowseGroup(rawValue: String(route.dropFirst(tripleJGroupPrefix.count)))
    }
}

enum TripleJBrowseGroup: String, CaseIterable, Identifiable {
    case national
    case specialty
    case stateFeeds

    var id: String { rawValue }
    var title: String {
        switch self {
        case .national: return "triple j"
        case .specialty: return "Specialty Music Stations"
        case .stateFeeds: return "State-based triple j feeds"
        }
    }
    var symbol: String {
        switch self {
        case .national: return "antenna.radiowaves.left.and.right"
        case .specialty: return "music.note.list"
        case .stateFeeds: return "map"
        }
    }
    func includes(_ station: DirectoryStation) -> Bool {
        guard station.network.caseInsensitiveCompare("ABC") == .orderedSame,
              station.subnetwork?.caseInsensitiveCompare("Triple J") == .orderedSame else { return false }
        switch self {
        case .national:
            return station.state.caseInsensitiveCompare("National") == .orderedSame
                && station.name.caseInsensitiveCompare("triple j") == .orderedSame
        case .specialty:
            return station.name.localizedCaseInsensitiveContains("Hottest")
                || station.name.localizedCaseInsensitiveContains("Unearthed")
        case .stateFeeds:
            return station.state.caseInsensitiveCompare("National") != .orderedSame
        }
    }
}

struct DiscoverLocationBrowseView: View {
    @ObservedObject var library: StationLibrary

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Browse by location").font(.system(size: metrics.detailTitle, weight: .bold)).padding(.horizontal, 2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tileMinimumWidth, maximum: metrics.tileMaximumWidth), spacing: metrics.tileSpacing)], spacing: metrics.tileSpacing) {
                        NavigationLink(value: DiscoverBrowseRoute.national) {
                            DiscoverBrowseTile(title: "National", subtitle: "Australia-wide stations", symbol: "antenna.radiowaves.left.and.right", metrics: metrics)
                        }.buttonStyle(.plain).accessibilityIdentifier("browseNational")
                        ForEach(DiscoverRegion.allCases) { region in
                            NavigationLink(value: region.rawValue) {
                                DiscoverBrowseTile(title: region.rawValue, symbol: region.symbol, metrics: metrics)
                            }.buttonStyle(.plain).accessibilityIdentifier("region-\(region.rawValue)")
                        }
                        NavigationLink(value: DiscoverBrowseRoute.otherLocations) {
                            DiscoverBrowseTile(title: "Other Locations", subtitle: "Find towns and regional stations", symbol: "map", metrics: metrics)
                        }.buttonStyle(.plain).accessibilityIdentifier("browseOtherLocations")
                    }
                    Text("Browse by State").font(.system(size: metrics.detailTitle, weight: .bold)).padding(.horizontal, 2).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tileMinimumWidth, maximum: metrics.tileMaximumWidth), spacing: metrics.tileSpacing)], spacing: metrics.tileSpacing) {
                        ForEach(AustralianBroadcastState.allCases) { state in
                            NavigationLink(value: DiscoverBrowseRoute.state(state.rawValue)) {
                                DiscoverBrowseTile(title: state.shortTitle, symbol: "map.fill", metrics: metrics)
                            }.buttonStyle(.plain).accessibilityIdentifier("state-\(state.rawValue)")
                        }
                    }
                }
                .padding(metrics.pagePadding)
                .padding(.bottom, metrics.discoverTileBottomClearance)
                .frame(maxWidth: metrics.playerMaximumWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await library.refresh() }
    }
}

struct NetworkSubnetwork: Identifiable {
    let name: String
    let symbol: String
    var id: String { name }
}

enum NetworkSubnetworkCatalogue {
    static func services(for network: String) -> [NetworkSubnetwork]? {
        switch network.lowercased() {
        case "abc":
            return [
                .init(name: "ABC Local Radio", symbol: "mappin.and.ellipse"), .init(name: "Radio National", symbol: "text.bubble"),
                .init(name: "ABC Sport", symbol: "sportscourt"), .init(name: "Triple J", symbol: "music.note"),
                .init(name: "Double J", symbol: "music.note.list"), .init(name: "ABC Classic", symbol: "music.quarternote.3"),
                .init(name: "News Radio", symbol: "newspaper"), .init(name: "ABC Country", symbol: "guitars"),
                .init(name: "ABC Jazz", symbol: "music.mic"), .init(name: "ABC Kids listen", symbol: "figure.2.and.child.holdinghands"),
                .init(name: "Radio Australia", symbol: "globe.asia.australia")
            ]
        case "triple m":
            return [.init(name: "Metro", symbol: "building.2"), .init(name: "Regional", symbol: "map"),
                    .init(name: "Music", symbol: "music.note.list"), .init(name: "Sport", symbol: "sportscourt")]
        case "hit network":
            return [.init(name: "Metro", symbol: "building.2"), .init(name: "Regional", symbol: "map"),
                    .init(name: "Music", symbol: "music.note.list")]
        case "kiis", "gold", "smooth":
            return [.init(name: "Metro", symbol: "building.2"),
                    .init(name: "Music", symbol: "music.note.list")]
        case "nova":
            return [.init(name: "Metro", symbol: "building.2"),
                    .init(name: "Music", symbol: "music.note.list"),
                    .init(name: "Talkback", symbol: "bubble.left.and.bubble.right"),
                    .init(name: "MediaWorks New Zealand", symbol: "globe.asia.australia")]
        case "community and specialist stations":
            return [.init(name: "Community", symbol: "person.3"),
                    .init(name: "Religion", symbol: "building.columns"),
                    .init(name: "Foreign Language", symbol: "globe"),
                    .init(name: "Country Music", symbol: "guitars"),
                    .init(name: "Indigenous", symbol: "sun.max"),
                    .init(name: "Arts & Music", symbol: "music.note.list"),
                    .init(name: "Radio Reading", symbol: "book"),
                    .init(name: "Youth & Education", symbol: "graduationcap"),
                    .init(name: "Seniors", symbol: "figure.2"),
                    .init(name: "LGBTQIA+", symbol: "rainbow")]
        default: return nil
        }
    }
}

enum NetworkBrowseOrdering {
    static let specialist = "Community and Specialist stations"
    static let uncategorised = "Not yet categorised"

    static func ordered(_ networks: [String]) -> [String] {
        networks.sorted { lhs, rhs in
            let leftRank = rank(lhs)
            let rightRank = rank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func rank(_ network: String) -> Int {
        if network == specialist { return 1 }
        if network == uncategorised { return 2 }
        return 0
    }
}

struct MajorNetwork: Identifiable {
    let directoryName: String
    let displayName: String
    var id: String { directoryName }
}

enum MajorNetworkCatalogue {
    static let all: [MajorNetwork] = [
        .init(directoryName: "ABC", displayName: "ABC"),
        .init(directoryName: "ACE Radio Network", displayName: "ACE Radio"),
        .init(directoryName: "ARN", displayName: "ARN Regional"),
        .init(directoryName: "Gold", displayName: "Gold"),
        .init(directoryName: "Heart", displayName: "Heart"),
        .init(directoryName: "Hit Network", displayName: "Hit"),
        .init(directoryName: "iHeart", displayName: "iHeart"),
        .init(directoryName: "KIIS", displayName: "KIIS"),
        .init(directoryName: "LiSTNR", displayName: "LiSTNR"),
        .init(directoryName: "Nova", displayName: "Nova"),
        .init(directoryName: "SBS Audio", displayName: "SBS Audio"),
        .init(directoryName: "SEN", displayName: "SEN"),
        .init(directoryName: "Smooth", displayName: "Smooth"),
        .init(directoryName: "Super Radio Network", displayName: "Super Radio Network"),
        .init(directoryName: "Tapt Media", displayName: "Tapt Media"),
        .init(directoryName: "Triple M", displayName: "Triple M")
    ].sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

    static func displayName(for directoryName: String) -> String {
        all.first { $0.directoryName == directoryName }?.displayName ?? directoryName
    }
}

struct NetworkSubnetworkView: View {
    @ObservedObject var library: StationLibrary
    let network: String

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose a \(network) service")
                        .font(.system(size: metrics.detailTitle, weight: .bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tileMinimumWidth, maximum: metrics.tileMaximumWidth), spacing: metrics.tileSpacing)], spacing: metrics.tileSpacing) {
                        ForEach(NetworkSubnetworkCatalogue.services(for: network) ?? []) { service in
                            NavigationLink(value: destination(for: service)) {
                                DiscoverBrowseTile(
                                    title: service.name,
                                    subtitle: stationCountText(service.name),
                                    symbol: service.symbol,
                                    metrics: metrics
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(network.lowercased().replacingOccurrences(of: " ", with: "-"))-subnetwork-\(service.name)")
                        }
                    }
                }
                .padding(metrics.pagePadding)
                .padding(.bottom, metrics.discoverTileBottomClearance)
                .frame(maxWidth: metrics.playerMaximumWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await library.refresh() }
    }

    private func stationCountText(_ subnetwork: String) -> String {
        let count = library.results(favouritesOnly: false, query: "", network: network, city: "", subnetwork: subnetwork).count
        return "\(count) \(count == 1 ? "station" : "stations")"
    }

    private func destination(for service: NetworkSubnetwork) -> String {
        if network.caseInsensitiveCompare("ABC") == .orderedSame,
           service.name.caseInsensitiveCompare("Triple J") == .orderedSame {
            return DiscoverBrowseRoute.tripleJ
        }
        return DiscoverBrowseRoute.subnetwork(network: network, value: service.name)
    }
}

struct TripleJBrowseView: View {
    @ObservedObject var library: StationLibrary

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose a triple j service")
                        .font(.system(size: metrics.detailTitle, weight: .bold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tileMinimumWidth, maximum: metrics.tileMaximumWidth), spacing: metrics.tileSpacing)], spacing: metrics.tileSpacing) {
                        ForEach(TripleJBrowseGroup.allCases) { group in
                            NavigationLink(value: DiscoverBrowseRoute.tripleJGroup(group)) {
                                DiscoverBrowseTile(
                                    title: group.title,
                                    subtitle: stationCountText(group),
                                    symbol: group.symbol,
                                    metrics: metrics
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("triple-j-group-\(group.rawValue)")
                        }
                    }
                }
                .padding(metrics.pagePadding)
                .padding(.bottom, metrics.discoverTileBottomClearance)
                .frame(maxWidth: metrics.playerMaximumWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await library.refresh() }
    }

    private func stationCountText(_ group: TripleJBrowseGroup) -> String {
        let count = library.stations.filter(group.includes).count
        return "\(count) \(count == 1 ? "station" : "stations")"
    }
}

struct DiscoverFacetView: View {
    enum Kind: Equatable { case networks, locations, genres }
    @ObservedObject var library: StationLibrary
    let kind: Kind
    @State private var query = ""

    private var values: [String] {
        let source = kind == .genres ? library.musicGenres.filter { $0 != "News" && $0 != "Sport" } : kind == .networks ? NetworkBrowseOrdering.ordered(library.networks).filter { $0 != NetworkBrowseOrdering.specialist } : library.cities.filter { city in
            !DiscoverRegion.allCases.contains { $0.rawValue.caseInsensitiveCompare(city) == .orderedSame }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source : source.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var majorNetworks: [MajorNetwork] {
        MajorNetworkCatalogue.all.filter { library.networks.contains($0.directoryName) }
    }

    private var allNetworks: [String] {
        library.networks
            .sorted {
                MajorNetworkCatalogue.displayName(for: $0).localizedStandardCompare(MajorNetworkCatalogue.displayName(for: $1)) == .orderedAscending
            }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WirelessLayoutMetrics(width: proxy.size.width)
            ScrollView {
                VStack(spacing: metrics.tileSpacing) {
                    if kind == .networks {
                        networkBrowseContent(metrics: metrics)
                    } else {
                    if kind == .genres, library.isLoading { ProgressView("Refreshing directory…") }
                    if kind == .genres, let error = library.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    if kind == .genres {
                        Text("Choose your music").font(.system(size: metrics.detailTitle, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if kind == .locations || kind == .genres {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(kind == .genres ? "Search genres" : "Search towns and locations", text: $query)
                                .textFieldStyle(.plain)
                                .accessibilityIdentifier(kind == .genres ? "genreSearch" : "locationSearch")
                            if !query.isEmpty {
                                Button {
                                    query = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(kind == .genres ? "Clear genre search" : "Clear location search")
                            }
                        }
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tileMinimumWidth, maximum: metrics.tileMaximumWidth), spacing: metrics.tileSpacing)], spacing: metrics.tileSpacing) {
                        ForEach(values, id: \.self) { value in
                            NavigationLink(value: kind == .genres ? DiscoverBrowseRoute.genre(value) : kind == .networks ? DiscoverBrowseRoute.network(value) : DiscoverBrowseRoute.location(value)) {
                                DiscoverBrowseTile(title: value, subtitle: stationCountText(value), symbol: kind == .genres ? "music.note.list" : kind == .networks ? "dot.radiowaves.left.and.right" : "mappin.and.ellipse", metrics: metrics)
                            }.buttonStyle(.plain).accessibilityIdentifier("browse-\(kind == .genres ? "genre" : kind == .networks ? "network" : "location")-\(value)")
                        }
                    }
                    }
                }
                .padding(metrics.pagePadding)
                .padding(.bottom, metrics.discoverTileBottomClearance)
                .frame(maxWidth: metrics.playerMaximumWidth)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if values.isEmpty {
                    if kind == .genres && query.isEmpty {
                        ContentUnavailableView("No genres available", systemImage: "music.note.list", description: Text(library.error ?? "Refresh the directory to see music genres as stations are categorised."))
                    } else { ContentUnavailableView.search(text: query) }
                }
            }
        }
        .task { await library.refresh() }
        .toolbar {
            if kind == .genres {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await library.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh genres").disabled(library.isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private func networkBrowseContent(metrics: WirelessLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.discoverSectionSpacing) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Major broadcasters")
                    .font(.system(size: metrics.detailTitle, weight: .bold, design: .rounded))
                Text("Browse Australia’s leading radio networks.")
                    .font(.system(size: metrics.secondary))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: metrics.networkTileMinimumWidth, maximum: metrics.networkTileMaximumWidth), spacing: metrics.tileSpacing)],
                spacing: metrics.tileSpacing
            ) {
                ForEach(majorNetworks) { network in
                    NavigationLink(value: DiscoverBrowseRoute.network(network.directoryName)) {
                        MajorNetworkTile(network: network, logoURL: library.networkArtworkURL(for: network.directoryName), stations: library.stations, metrics: metrics)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browse-network-\(network.directoryName)")
                }
            }

            Text("All Networks")
                .font(.system(size: metrics.discoverSectionTitle, weight: .bold, design: .rounded))
                .padding(.top, max(18, metrics.discoverSectionSpacing))

            LazyVStack(spacing: 0) {
                ForEach(allNetworks, id: \.self) { network in
                    NavigationLink(value: DiscoverBrowseRoute.network(network)) {
                        HStack(spacing: 12) {
                            Image(systemName: "radio")
                                .font(.system(size: metrics.primary, weight: .semibold))
                                .foregroundStyle(.purple)
                                .frame(width: 34, height: 34)
                                .background(.purple.opacity(0.12), in: Circle())
                            Text(MajorNetworkCatalogue.displayName(for: network))
                                .font(.system(size: metrics.primary, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(stationCountText(network))
                                .font(.system(size: metrics.secondary))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("all-network-\(network)")
                    if network != allNetworks.last { Divider().padding(.leading, 46) }
                }
            }
            .padding(.horizontal, 14)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func stationCountText(_ value: String) -> String {
        let count = kind == .genres
            ? library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: value).count
            : kind == .networks
            ? library.results(favouritesOnly: false, query: "", network: value, city: "").count
            : library.results(favouritesOnly: false, query: "", network: "", city: value).count
        return "\(count) \(count == 1 ? "station" : "stations")"
    }
}

private struct MajorNetworkTile: View {
    let network: MajorNetwork
    let logoURL: URL?
    let stations: [DirectoryStation]
    let metrics: WirelessLayoutMetrics

    private var stationCount: Int { stations.count { $0.network == network.directoryName } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                NetworkBrandMark(network: network, logoURL: logoURL)
                .frame(width: metrics.networkLogoSize, height: metrics.networkLogoSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(network.displayName)
                .font(.system(size: metrics.primary, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("\(stationCount) \(stationCount == 1 ? "station" : "stations")")
                .font(.system(size: metrics.secondary))
                .foregroundStyle(.secondary)
        }
        .padding(metrics.discoverTilePadding)
        .frame(maxWidth: .infinity, minHeight: metrics.networkTileHeight, alignment: .leading)
        .background(
            LinearGradient(colors: [.purple.opacity(0.18), .white.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.purple.opacity(0.18), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct NetworkBrandMark: View {
    let network: MajorNetwork
    let logoURL: URL?

    var body: some View {
        ZStack {
            network.directoryName == "ARN" ? Color.black : Color.clear
            AsyncImage(url: logoURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } placeholder: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.purple)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
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
