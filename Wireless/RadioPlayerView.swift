import SwiftUI
import AVKit

// Adapted from Autohop PlayerView: glass pills, purple play circle,
// artwork glow, paged panes and container-based sizing.
private extension View {
    func playerPill(highlighted: Bool = false) -> some View {
        self.padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(highlighted ? .regular.tint(.purple) : .regular,
                         in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AudioControlsSheet: View {
    @ObservedObject var player: MobilePlayer
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio stream") {
                    Picker("Stream", selection: $player.selectedStreamID) {
                        ForEach(player.station.playableStreams) { stream in
                            Text(stream.title).tag(stream.id)
                        }
                    }
                    .accessibilityIdentifier("streamPicker")
                }
                Section {
                    Picker("Vocal Boost", selection: $player.vocalBoost) {
                        ForEach(VocalBoostLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(player.syncEnabled)
                    .accessibilityIdentifier("vocalBoostPicker")
                } header: {
                    Text("Vocal Boost")
                } footer: {
                    Text(vocalBoostHelp)
                }
                Section {
                    Text("Choose an alternative stream if reception is unreliable.")
                    Text("Delay controls are available when the broadcaster provides a seekable live buffer.")
                    Text("Use the Sync pane to match commentary to your television.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Audio Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                }
            }
        }
        .presentationBackground(.regularMaterial)
        .presentationDetents([.medium, .large])
    }

    private var vocalBoostHelp: String {
        if player.syncEnabled { return "Vocal Boost is disabled while TV Sync is on." }
        return "Light, Standard and Strong use enhanced AVAudioEngine playback for compatible direct MP3 and AAC streams. Other streams and Off use AVPlayer."
    }
}

struct RadioPlayerView: View {
    @ObservedObject var player: MobilePlayer
    @ObservedObject private var library: StationLibrary
    @ObservedObject private var sleepTimer: SleepTimerService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("keepScreenAwakeDuringPlayback") private var keepScreenAwake = false
    @State private var pane = PlayerPane.playing
    @State private var path: [String] = []
    @State private var showFavourites = false
    @State private var showAudio = false
    @State private var showSleepTimer = false

    init(player: MobilePlayer) {
        self.player = player
        self.library = player.library
        self.sleepTimer = player.sleepTimer
        _path = State(initialValue: player.shouldOpenDiscoverOnLaunch ? ["Discover"] : [])
    }

    private var visiblePanes: [PlayerPane] {
        player.hasDetails ? [.playing, .details, .sync] : [.playing, .sync]
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    topBar(width: geometry.size.width)
                    TabView(selection: $pane) {
                        playing(size: geometry.size).accessibilityHidden(pane != .playing).tag(PlayerPane.playing)
                        if player.hasDetails {
                            details(size: geometry.size).accessibilityHidden(pane != .details).tag(PlayerPane.details)
                        }
                        sync(size: geometry.size).accessibilityHidden(pane != .sync).tag(PlayerPane.sync)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .padding(.top, 8)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                Group {
                    if destination == "Discover" { stationList(favouritesOnly: false) }
                    else if destination == DiscoverBrowseRoute.national { stationList(favouritesOnly: false, state: "National") }
                    else if let region = DiscoverRegion(rawValue: destination) { stationList(favouritesOnly: false, region: region) }
                    else if destination == DiscoverBrowseRoute.networks { DiscoverFacetView(library: library, kind: .networks) }
                    else if destination == DiscoverBrowseRoute.locations { DiscoverFacetView(library: library, kind: .locations) }
                    else if let network = DiscoverBrowseRoute.networkValue(destination) { stationList(favouritesOnly: false, network: network) }
                    else if let city = DiscoverBrowseRoute.locationValue(destination) { stationList(favouritesOnly: false, city: city) }
                    else if let state = DiscoverBrowseRoute.stateValue(destination) { stationList(favouritesOnly: false, state: state) }
                    else { EmptyView() }
                }
                .navigationTitle(discoverTitle(destination))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .background(Color.black)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            }
        }
        .sheet(isPresented: $showFavourites) {
            FavouritesView(
                library: library,
                currentID: player.station.id,
                isPlaying: player.requested,
                play: { station in player.playStation(station); pane = .playing; showFavourites = false },
                browse: { showFavourites = false; path = ["Discover"] },
                close: { showFavourites = false }
            )
        }
        .sheet(isPresented: $showAudio) {
            AudioControlsSheet(player: player) { showAudio = false }
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheetView(sleepTimer: sleepTimer)
        }
        .onChange(of: scenePhase) { _, phase in
            player.sceneChanged(phase)
            if phase == .active { pane = .playing }
            updateIdleTimer()
        }
        .onChange(of: player.requested) { _, _ in updateIdleTimer() }
        .onChange(of: path) { _, _ in updateIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in updateIdleTimer() }
        .onAppear { updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: player.hasDetails) { _, available in
            if !available && pane == .details { pane = .playing }
        }
    }

    private func updateIdleTimer() {
        let shouldStayAwake = keepScreenAwake
            && player.requested
            && path.isEmpty
            && scenePhase == .active
        guard UIApplication.shared.isIdleTimerDisabled != shouldStayAwake else { return }
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }

    private func topBar(width: CGFloat) -> some View {
        let metrics = WirelessLayoutMetrics(width: width)
        return HStack(spacing: 8) {
            Button { path.append("Discover") } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: metrics.navigationFont, weight: .semibold))
                    .frame(width: metrics.navigationControl, height: metrics.navigationControl)
                    .glassEffect(in: Circle())
            }.foregroundStyle(.white).accessibilityLabel("Discover")
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(visiblePanes) { item in
                    let selected = pane == item
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { pane = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: metrics.navigationFont, weight: .semibold))
                            if selected {
                                Text(item.title)
                                    .font(.system(size: metrics.navigationFont, weight: .semibold))
                                    .transition(.opacity)
                            }
                        }
                        .foregroundStyle(selected ? .white : .secondary)
                        .padding(.horizontal, selected ? 12 : 9).frame(height: metrics.navigationControl)
                        .background(selected ? Color.white.opacity(0.12) : .clear, in: Capsule())
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            Button { showFavourites = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "heart")
                        .font(.system(size: metrics.navigationFont, weight: .bold))
                    Text("\(library.favourites.count)")
                        .font(.system(size: metrics.navigationFont * 0.8, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.purple.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: metrics.navigationControl)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9))
            }.accessibilityLabel("Favourites, \(library.favourites.count) stations")
        }.padding(.horizontal, 16)
    }

    private func playing(size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                let side = max(100, size.width - 44)
                StationImage(station: player.station, cornerRadius: 20).frame(width: side, height: side)
                    .background { Circle().fill(.purple.opacity(0.34)).blur(radius: 45) }
                    .padding(.top, 11)
                VStack(spacing: 6) {
                    Text(player.station.name)
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                    if !player.syncEnabled, let track = player.trackMetadata {
                        Text([track.title, track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityLabel("\(track.title), by \(track.artist)" + (track.album.map { ", from \($0)" } ?? ""))
                            .accessibilityIdentifier("currentTrackTitle")
                    } else {
                        if player.displayTitle != player.station.name {
                            Text(player.displayTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Text([player.station.network, player.station.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                liveProgress
                    .padding(.horizontal, 22)

                Button { player.toggle() } label: {
                    Image(systemName: player.requested ? "pause.fill" : "play.fill")
                        .font(.system(size: 28)).foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular.tint(.purple), in: Circle())
                        .shadow(color: .purple.opacity(0.35), radius: 14)
                }.accessibilityLabel(player.requested ? "Pause" : "Play")
                playerActionRow
                favouriteShortcuts
            }.frame(maxWidth: 620).padding(.horizontal, 22).padding(.bottom, 30)
                .frame(maxWidth: .infinity)
        }
    }

    private var shortcutFavourites: [DirectoryStation] {
        Array(library.favourites.lazy
            .filter { $0.id != player.station.id && $0.preferredStream != nil }
            .prefix(2))
    }

    @ViewBuilder
    private var favouriteShortcuts: some View {
        let stations = shortcutFavourites
        if !stations.isEmpty {
            HStack(spacing: 12) {
                ForEach(stations) { station in
                    Button {
                        player.playStation(station)
                        pane = .playing
                    } label: {
                        HStack(spacing: 10) {
                            StationImage(station: station, cornerRadius: 10)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(station.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text([station.network, station.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play favourite \(station.name)")
                    .accessibilityIdentifier("favouriteShortcut-\(station.id)")
                }
                if stations.count == 1 {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 76)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 5)
        }
    }

    private var liveProgress: some View {
        let delayed = player.syncEnabled && player.delay > 0
        let position = delayed ? max(0.04, 1 - player.delay / 30) : 1.0
        let showingBufferProgress = player.buffering && player.requested
        let displayedProgress = showingBufferProgress ? min(1, max(0, player.progress)) : position
        return VStack(spacing: 7) {
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                    Capsule().fill(Color.purple).frame(width: trackWidth * displayedProgress, height: 5)
                    Circle().fill(.white)
                        .frame(width: 22, height: 22)
                        .offset(x: max(0, min(trackWidth - 22, trackWidth * displayedProgress - 11)))
                }.frame(maxHeight: .infinity)
            }
            .frame(height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(showingBufferProgress ? "Buffering progress" : (delayed ? "Delayed for TV Sync" : "Live"))
            .accessibilityValue(showingBufferProgress
                                ? "\(Int((displayedProgress * 100).rounded())) per cent"
                                : (delayed ? String(format: "%.1f seconds behind live", player.delay) : "At live edge"))

            HStack {
                Text(player.syncEnabled ? "Sync Enabled" : player.status)
                    .accessibilityIdentifier("playbackStatus")
                Spacer()
                Text(progressDetail(showingBufferProgress: showingBufferProgress,
                                    displayedProgress: displayedProgress,
                                    delayed: delayed))
                    .accessibilityIdentifier("playbackPositionDetail")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()

        }
    }

    private func progressDetail(showingBufferProgress: Bool, displayedProgress: Double, delayed: Bool) -> String {
        if player.syncEnabled {
            return player.measured.map { String(format: "Measured: %.1f s", $0) } ?? "Measuring…"
        }
        if showingBufferProgress { return "\(Int((displayedProgress * 100).rounded()))%" }
        return delayed ? String(format: "%.1f s behind Live", player.delay) : "At live edge"
    }

    private func details(size: CGSize) -> some View {
        let metrics = WirelessLayoutMetrics(width: size.width)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(player.station.name)
                    .font(.system(size: metrics.detailTitle, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                StationImage(station: player.station, cornerRadius: 14, isDecorative: false)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: metrics.detailsMediaMaximumWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("detailsStationArtwork")
                    .accessibilityLabel("Artwork for \(player.station.name)")
                    .padding(.bottom, 16)

                let description = player.station.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Station Description")
                            .font(.system(size: metrics.detailsMetaKeyFont, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(Color(white: 0.42))
                        Text(description)
                            .font(.system(size: metrics.detailBody))
                            .foregroundStyle(Color(white: 0.78))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    .accessibilityIdentifier("stationDescriptionCard")
                    .padding(.bottom, 16)
                }

                GlassEffectContainer(spacing: 8) {
                    detailsMetaGrid(metrics: metrics)
                }
                .accessibilityIdentifier("stationMetadataGrid")
                .padding(.bottom, 18)

                if let contact = player.station.contact {
                    let phoneNumbers = [contact.talkback_phone, contact.sms, contact.office_phone]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !phoneNumbers.isEmpty || !(contact.email ?? "").isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Contact").font(.system(size: metrics.primary, weight: .bold))
                            if let phone = contact.talkback_phone, !phone.isEmpty { contactRows("Talkback", value: phone, symbol: "phone", kind: .telephone) }
                            if let sms = contact.sms, !sms.isEmpty { contactRows("SMS", value: sms, symbol: "message", kind: .message) }
                            if let office = contact.office_phone, !office.isEmpty { contactRows("Office", value: office, symbol: "building.2", kind: .telephone) }
                            if let email = contact.email, !email.isEmpty { contactRows("Email", value: email, symbol: "envelope", kind: .email) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .padding(.bottom, 18)
                    }
                }

                if let current = player.guide.current {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current programme").font(.system(size: metrics.primary, weight: .bold))
                        Text(current.name).font(.system(size: metrics.primary, weight: .semibold))
                        if let presenter = current.presenter {
                            Text(presenter).font(.system(size: metrics.secondary)).foregroundStyle(.secondary)
                        }
                        Text(current.timeLabel).font(.system(size: metrics.secondary)).foregroundStyle(.secondary)
                    }
                    if !player.guide.upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Coming up").font(.system(size: metrics.primary, weight: .bold))
                            ForEach(player.guide.upcoming.prefix(3)) { programme in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(programme.name).font(.system(size: metrics.primary, weight: .semibold))
                                    Text(programme.timeLabel).font(.system(size: metrics.secondary)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let website = URL(string: player.station.website_url),
                   website.scheme == "https" || website.scheme == "http" {
                    Link(destination: website) {
                        Label("Station website", systemImage: "safari")
                            .font(.system(size: metrics.primary, weight: .semibold))
                    }
                    .padding(.bottom, 30)
                }
            }
            .padding(.horizontal, metrics.detailsGutter)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func detailsMetaGrid(metrics: WirelessLayoutMetrics) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: metrics.detailsMetaCardMinimumWidth), spacing: 10)],
            spacing: 10
        ) {
            if !player.station.cities.isEmpty {
                metaCard("Station location", player.station.cities.joined(separator: ", "), metrics: metrics)
            }
            if !player.station.state.isEmpty {
                metaCard("Station state", australianStateName(player.station.state), metrics: metrics)
            }
            ForEach(Array(uniqueGenres.enumerated()), id: \.offset) { _, genre in
                metaCard("Genre", genre, metrics: metrics)
            }
            if let stream = selectedStream {
                metaCard("Stream type", stream.format.uppercased(), metrics: metrics)
                if let bitrate = stream.bitrate_kbps {
                    metaCard("Stream bitrate", "\(Int(bitrate.rounded())) kbps", metrics: metrics)
                }
            }
        }
    }

    private func metaCard(_ key: String, _ value: String, metrics: WirelessLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: metrics.detailsMetaKeyFont, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Color(white: 0.33))
            Text(value)
                .font(.system(size: metrics.detailBody, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationMetadata-\(key)-\(value)")
    }

    private var selectedStream: StationStream? {
        player.station.playableStreams.first { $0.id == player.selectedStreamID }
            ?? player.station.preferredStream
    }

    private var uniqueGenres: [String] {
        var seen = Set<String>()
        return (player.station.genres ?? []).compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return trimmed.capitalized
        }
    }

    private func australianStateName(_ abbreviation: String) -> String {
        let names = [
            "ACT": "Australian Capital Territory", "NSW": "New South Wales",
            "NT": "Northern Territory", "QLD": "Queensland", "SA": "South Australia",
            "TAS": "Tasmania", "VIC": "Victoria", "WA": "Western Australia"
        ]
        return names[abbreviation.uppercased()] ?? abbreviation
    }

    @ViewBuilder
    private func contactRows(_ label: String, value: String, symbol: String, kind: ContactLinkKind) -> some View {
        let values = value.split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        ForEach(Array(values.enumerated()), id: \.offset) { index, entry in
            if let destination = contactURL(for: entry, kind: kind) {
                Link(destination: destination) {
                    contactRowLabel(values.count > 1 ? "\(label) \(index + 1)" : label, value: entry, symbol: symbol)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationContact-\(label)-\(index)")
                .accessibilityHint(kind.accessibilityHint)
            } else {
                contactRowLabel(label, value: entry, symbol: symbol)
            }
        }
    }

    private func contactRowLabel(_ label: String, value: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.purple).frame(width: 24)
        }
        .contentShape(Rectangle())
    }

    private func contactURL(for value: String, kind: ContactLinkKind) -> URL? {
        switch kind {
        case .email:
            let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: "mailto:\(address)")
        case .telephone, .message:
            let allowed = Set("+0123456789")
            var number = value.filter { allowed.contains($0) }
            if number.hasPrefix("00") { number = "+" + String(number.dropFirst(2)) }
            guard number.contains(where: \.isNumber) else { return nil }
            return URL(string: "\(kind == .telephone ? "tel" : "sms"):\(number)")
        }
    }

    private var playerActionRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { showAudio = true } label: { playerActionIcon("slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel("Audio Controls")
                Button { showSleepTimer = true } label: { sleepTimerButtonLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sleep Timer")
            }
            .frame(width: 96, alignment: .leading)

            audioSourceButton
                .frame(maxWidth: .infinity, alignment: .center)

            Button { library.toggle(player.station) } label: {
                HStack(spacing: 6) {
                    Image(systemName: library.contains(player.station) ? "heart.fill" : "heart")
                    Text(library.contains(player.station) ? "Unfavourite" : "Favourite")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.purple)
                .frame(width: 96, height: 32)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(library.contains(player.station) ? "Remove \(player.station.name) from Favourites" : "Add \(player.station.name) to Favourites")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var audioSourceButton: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "airplayaudio")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.purple.opacity(0.9))
                    .fixedSize()

                Text(player.route)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .allowsHitTesting(false)

            AudioRoutePickerView(tintColor: .clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.02)
                .accessibilityLabel("Choose audio output")
                .accessibilityHint("Opens AirPlay and connected audio devices")
        }
        .frame(minWidth: 48, maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityIdentifier("audioSourceSelector")
    }

    private func playerActionIcon(_ systemName: String, highlighted: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(highlighted ? Color.white : Color.purple)
            .frame(width: 44, height: 32)
            .glassEffect(highlighted ? .regular.tint(.purple) : .regular,
                         in: RoundedRectangle(cornerRadius: 9))
    }

    private var sleepTimerButtonLabel: some View {
        ZStack(alignment: .topTrailing) {
            playerActionIcon(sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz",
                             highlighted: sleepTimer.isActive)

            if let badge = sleepTimerBadge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.purple, in: Capsule())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var sleepTimerBadge: String? {
        let remaining = sleepTimer.timeRemaining
        guard remaining.isFinite, remaining >= 0 else { return nil }
        let total = Int(remaining)
        if total >= 3_600 { return "\(total / 3_600)h" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func sync(size: CGSize) -> some View {
        let metrics = WirelessLayoutMetrics(width: size.width)
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match the moment").font(.system(size: metrics.detailTitle, weight: .bold))
                    Text("Delay the radio commentary to line up with your television picture.")
                        .font(.system(size: metrics.detailBody)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Sync audio to picture", isOn: $player.syncEnabled)
                        .font(.headline)
                        .accessibilityIdentifier("syncEnabled")
                    Text(player.syncEnabled
                         ? "Use your saved delay to match the television picture."
                         : "Sync is off. Wireless returns to the live stream and uses a short reliability buffer for smooth, stable playback. Your delay setting is saved.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(22).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                VStack(spacing: 22) {
                    Text(player.syncEnabled ? "Audio delay" : "Saved audio delay").font(.headline)
                    Text(String(format: "%.1f s", player.delay))
                        .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    Slider(value: $player.delay, in: 0...30, step: 0.5)
                        .accessibilityLabel("Audio delay")
                        .accessibilityValue(String(format: "%.1f seconds", player.delay))
                    HStack {
                        Button { player.adjust(-0.5) } label: { Label("0.5 s", systemImage: "minus").playerPill() }
                            .disabled(player.delay <= 0).accessibilityLabel("Decrease delay by half a second")
                        Spacer()
                        Button { player.adjust(0.5) } label: { Label("0.5 s", systemImage: "plus").playerPill() }
                            .disabled(player.delay >= 30).accessibilityLabel("Increase delay by half a second")
                    }.frame(minHeight: 44)
                    LabeledContent("Measured stream delay", value: player.syncEnabled ? (player.measured.map { String(format: "%.1f s", $0) } ?? "—") : "Off")
                        .font(.subheadline).monospacedDigit()
                }.disabled(!player.syncEnabled || !player.supportsDelay)
                    .padding(22).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                if player.syncEnabled && !player.supportsDelay { Text("This stream format does not provide audio Wireless can retain for Sync.").foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 10) {
                    Text(player.status).font(.headline)
                    Text(player.detail).foregroundStyle(.secondary)
                    if player.buffering && player.requested { ProgressView(value: player.progress) }
                    Button(player.requested ? "Pause" : "Play", systemImage: player.requested ? "pause.fill" : "play.fill") { player.toggle() }
                        .buttonStyle(.borderedProminent)
                }
                if player.syncEnabled {
                Text("Wireless retains compatible MP3, AAC and AAC HLS audio for Sync. Other HLS formats depend on the broadcaster providing a seekable live window.")
                Text("Measured delay excludes broadcaster and wireless speaker latency. AirPlay and AirPods can add delay beyond this value.")
                    .foregroundStyle(.secondary)
                } else {
                    Text("Turning Sync off returns playback to the live stream. Wireless buffers around five seconds where the stream format allows, then plays without TV-delay correction. Audio quality remains as supplied by the broadcaster.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
    }

    private func stationList(favouritesOnly: Bool, region: DiscoverRegion? = nil, network: String = "", city: String = "", state: String = "") -> some View {
        DiscoverView(library: player.library, currentID: player.station.id, isPlaying: player.requested, favouritesOnly: favouritesOnly, play: { station in
            player.playStation(station); showFavourites = false; path = []; pane = .playing
        }, browse: {
            showFavourites = false; path = ["Discover"]
        }, region: region, networkFilter: network, cityFilter: city, stateFilter: state)
    }

    private func discoverTitle(_ destination: String) -> String {
        if destination == DiscoverBrowseRoute.networks { return "Networks" }
        if destination == DiscoverBrowseRoute.locations { return "Other Locations" }
        if destination == DiscoverBrowseRoute.national { return "National" }
        if let network = DiscoverBrowseRoute.networkValue(destination) { return network }
        if let city = DiscoverBrowseRoute.locationValue(destination) { return city }
        if let state = DiscoverBrowseRoute.stateValue(destination) { return state }
        return destination
    }

    private var miniPlayer: some View {
        WirelessMiniPlayerBar(
            player: player,
            openPlayer: { path = []; pane = .playing }
        )
    }
}

/// Wireless adaptation of Autohop's persistent MiniPlayerBar. Its layout,
/// responsive geometry, progress strip and continuous bottom glass surface are
/// kept aligned with Autohop while live radio exposes only Play/Pause.
private struct WirelessMiniPlayerBar: View {
    @ObservedObject var player: MobilePlayer
    @State private var viewportWidth: CGFloat = 390
    let openPlayer: () -> Void

    init(
        player: MobilePlayer,
        openPlayer: @escaping () -> Void
    ) {
        self.player = player
        self.openPlayer = openPlayer
    }

    var body: some View {
        if player.hasDetails {
            GeometryReader { geometry in
                let metrics = WirelessLayoutMetrics(width: geometry.size.width)
                let artworkSize = metrics.miniPlayerArtworkSize

                VStack(spacing: 0) {
                    HStack(spacing: 11) {
                        StationImage(station: player.station, cornerRadius: 8)
                            .frame(width: artworkSize, height: artworkSize)
                            .accessibilityIdentifier("miniPlayerArtwork")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(primaryTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)

                            HStack(spacing: metrics.miniPlayerSpacing) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(secondaryTitle)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.white.opacity(0.58))
                                        .lineLimit(1)
                                    Text(statusTitle)
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.42))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                compactControl(
                                    label: player.requested ? "Pause" : "Play",
                                    highlighted: true,
                                    action: player.toggle
                                ) {
                                    Image(systemName: player.requested ? "pause.fill" : "play.fill")
                                        .font(.system(size: metrics.miniPlayerControlSize * 0.36, weight: .bold))
                                        .offset(x: player.requested ? 0 : 1)
                                        .frame(width: metrics.miniPlayerControlSize, height: metrics.miniPlayerControlSize)
                                }
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, metrics.miniPlayerGutter)
                    .padding(.vertical, 7)

                    GeometryReader { progressGeometry in
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.purple)
                                    .frame(width: progressGeometry.size.width * progress)
                            }
                    }
                    .frame(height: 3)
                }
                .modifier(WirelessPersistentMiniPlayerSurface())
                .contentShape(Rectangle())
                .onTapGesture(perform: openPlayer)
                .accessibilityRepresentation {
                    HStack {
                        Button("Return to Player", action: openPlayer)
                        Button(player.requested ? "Pause" : "Play", action: player.toggle)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .frame(height: miniPlayerHeight)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                viewportWidth = width
            }
        }
    }

    private var primaryTitle: String {
        if !player.syncEnabled, let track = player.trackMetadata { return track.title }
        return player.station.name
    }

    private var secondaryTitle: String {
        if !player.syncEnabled, let track = player.trackMetadata { return track.artist }
        return player.station.name
    }

    private var statusTitle: String {
        if !player.syncEnabled, let album = player.trackMetadata?.album, !album.isEmpty { return album }
        return player.status
    }

    private var progress: Double {
        if player.buffering && player.requested { return min(1, max(0, player.progress)) }
        if player.syncEnabled && player.delay > 0 { return max(0.04, 1 - player.delay / 30) }
        return 1
    }

    private var miniPlayerHeight: CGFloat {
        WirelessLayoutMetrics(width: viewportWidth).miniPlayerArtworkSize + 17
    }

    private func compactControl<Label: View>(
        label: String,
        highlighted: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Label
    ) -> some View {
        Button(action: action) {
            if highlighted {
                content().modifier(WirelessMiniPlayerPrimaryControlSurface())
            } else {
                content()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct WirelessPersistentMiniPlayerSurface: ViewModifier {
    private let shape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(
            topLeading: 20,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 20
        ),
        style: .continuous
    )

    func body(content: Content) -> some View {
        content.background {
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(Color.purple.opacity(0.12)) }
                .glassEffect(.regular.tint(.purple.opacity(0.12)), in: shape)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

private struct WirelessMiniPlayerPrimaryControlSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint(.purple), in: Circle())
    }
}

private enum ContactLinkKind {
    case telephone
    case message
    case email

    var accessibilityHint: String {
        switch self {
        case .telephone: "Starts a phone call"
        case .message: "Starts a new message"
        case .email: "Starts a new email"
        }
    }
}

private enum PlayerPane: Int, Identifiable {
    case playing
    case details
    case sync

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .playing: "Playing"
        case .details: "Details"
        case .sync: "Sync"
        }
    }
    var icon: String {
        switch self {
        case .playing: "waveform"
        case .details: "info.circle"
        case .sync: "dot.radiowaves.left.and.right"
        }
    }
}
