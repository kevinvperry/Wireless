import CarPlay
import Combine
import Foundation
import UIKit

// ============================================================================
// AI CONTEXT - CarPlay/CarPlayCoordinator.swift
//
// PURPOSE: Coordinator for Wireless's CarPlay scene, adapted from Autohop's
// CarPlayCoordinator. It owns the CPInterfaceController reference while CarPlay
// is connected, installs a safe root template immediately and projects the
// shared MobilePlayer/StationLibrary into CarPlay templates. It never creates a
// separate CarPlay player, favourites list or settings model.
//
// TEMPLATE STACK (CarPlay audio apps allow a depth of 5):
//  - Loading: CPListTemplate root only (depth 1).
//  - Station chosen: CPNowPlayingTemplate root -> Favourites -> Discover ->
//    category (Networks, Locations, Music, Community & Specialist) -> station
//    list (depth 5). News and Talkback and Sport open their station list
//    directly from Discover (depth 4).
//  - No station chosen yet: Favourites is the root, so the same paths are one
//    level shallower.
//  - The Now Playing top-right button is CarPlay's built-in Up Next button,
//    retitled "Favourites" exactly as Autohop retitles it "Up Next".
//    CPNowPlayingTemplate does not accept custom navigation bar buttons.
//  - Favourites carries a trailing "Discover" bar button, mirroring Autohop's
//    Up Next -> Subscriptions bar button, and a Recently Played section.
//  - Discover offers the iPhone Discover page's six options. To stay within
//    the depth limit, a network with services (ABC, Triple M and so on) lists
//    its stations grouped by service instead of the iPhone's extra service
//    page, and Locations omits the iPhone's Other Locations town list.
//  - Selecting a station plays it and returns to the Now Playing root.
//
// Connecting CarPlay must not activate audio by itself except through the
// user's Auto Resume setting, matching the iPhone launch behaviour. Never
// switch to CPNowPlayingTemplate before a station has been chosen; otherwise
// CarPlay shows Apple's blank player shell.
// ============================================================================

@MainActor
final class CarPlayCoordinator: NSObject {
    private(set) weak var interfaceController: CPInterfaceController?
    private var readinessTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let presenter = CarPlayStationPresenter()
    private let artworkProvider = CarPlayArtworkProvider()

    private var favouritesTemplate: CPListTemplate?
    private var discoverTemplate: CPListTemplate?
    private var categoryTemplate: CPListTemplate?
    private var selectedCategory: BrowseCategory?
    private var destinationTemplate: CPListTemplate?
    private var selectedDestination: CarPlayStationDestination?
    private var rootRoute: RootRoute = .loading
    private var lastSnapshot: Snapshot?

    private enum RootRoute {
        case loading
        case nowPlaying
        case favourites
    }

    /// Discover options that open a further list before reaching stations.
    private enum BrowseCategory: Equatable {
        case networks
        case locations
        case music
        case specialist

        var title: String {
            switch self {
            case .networks: return "Networks"
            case .locations: return "Locations"
            case .music: return "Music"
            case .specialist: return "Community & Specialist"
            }
        }
    }

    private struct Snapshot: Equatable {
        let currentStationID: String
        let hasStation: Bool
        let isPlaying: Bool
        let favouriteIDs: [String]
        let recentIDs: [String]
        let catalogueCount: Int
        let isLoading: Bool

        @MainActor
        init(player: MobilePlayer) {
            currentStationID = player.station.id
            hasStation = player.hasDetails
            isPlaying = player.requested
            favouriteIDs = player.library.favourites.map(\.id)
            recentIDs = player.library.recents.map(\.id)
            catalogueCount = player.library.stations.count
            isLoading = player.library.isLoading
        }
    }

    private var player: MobilePlayer { MobilePlayer.shared }

    func connect(interfaceController: CPInterfaceController) {
        diagnose("carplay.connect", "CarPlay interface connected")
        self.interfaceController = interfaceController
        configureNowPlayingTemplate()
        setRootTemplate(makeLoadingTemplate(), animated: false)
        startReadinessFlow(for: interfaceController)
    }

    func disconnect(interfaceController: CPInterfaceController) {
        guard self.interfaceController === interfaceController else { return }
        readinessTask?.cancel()
        readinessTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        cancellables.removeAll()
        CPNowPlayingTemplate.shared.remove(self)
        clearPushedTemplates()
        favouritesTemplate = nil
        rootRoute = .loading
        lastSnapshot = nil
        self.interfaceController = nil
        diagnose("carplay.disconnect", "CarPlay interface disconnected")
    }

    private func startReadinessFlow(for interfaceController: CPInterfaceController) {
        readinessTask?.cancel()
        readinessTask = Task { @MainActor [weak self, weak interfaceController] in
            guard let self, let interfaceController else { return }
            let player = self.player
            player.autoResumeIfEnabled()
            guard !Task.isCancelled, self.interfaceController === interfaceController else { return }
            self.observePlayer()
            self.showInitialTemplate(animated: true)
            let isStale = player.library.refreshedAt.map { Date().timeIntervalSince($0) > 3_600 } ?? true
            if player.library.stations.isEmpty || isStale {
                await player.library.refresh()
            }
        }
    }

    // MARK: - Root

    private func showInitialTemplate(animated: Bool) {
        if player.hasDetails {
            configureNowPlayingButtons()
            rootRoute = .nowPlaying
            diagnose("carplay.root", "Showing Now Playing root", metadata: ["stationID": player.station.id])
            setRootTemplate(CPNowPlayingTemplate.shared, animated: animated)
        } else {
            rootRoute = .favourites
            diagnose("carplay.root", "Showing Favourites root", metadata: ["favourites": "\(player.library.favourites.count)"])
            let template = makeFavouritesTemplate()
            favouritesTemplate = template
            setRootTemplate(template, animated: animated)
        }
        lastSnapshot = Snapshot(player: player)
    }

    private func makeLoadingTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Wireless", sections: [])
        template.emptyViewTitleVariants = ["Loading Wireless"]
        if #available(iOS 18.4, *) {
            template.showsSpinnerWhileEmpty = true
        }
        return template
    }

    private func clearPushedTemplates() {
        discoverTemplate = nil
        categoryTemplate = nil
        selectedCategory = nil
        destinationTemplate = nil
        selectedDestination = nil
    }

    // MARK: - Favourites

    private func makeFavouritesTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Favourites", sections: makeFavouriteSections())
        template.emptyViewTitleVariants = ["No favourites yet"]
        template.emptyViewSubtitleVariants = ["Choose Discover to find a station."]
        template.trailingNavigationBarButtons = [makeDiscoverBarButton()]
        return template
    }

    private func makeFavouriteSections() -> [CPListSection] {
        let favourites = presenter.favouriteRows(from: player)
        let recents = presenter.recentRows(from: player)
        var sections: [CarPlayStationSection] = []
        if !favourites.isEmpty {
            sections.append(CarPlayStationSection(header: recents.isEmpty ? nil : "Favourites", rows: favourites))
        }
        if !recents.isEmpty {
            sections.append(CarPlayStationSection(header: "Recently Played", rows: recents))
        }
        return listSections(sections)
    }

    private func showFavouritesTemplate() {
        let template = makeFavouritesTemplate()
        favouritesTemplate = template
        pushTemplate(template, animated: true)
    }

    private func makeDiscoverBarButton() -> CPBarButton {
        let button = CPBarButton(title: "Discover") { [weak self] _ in
            Task { @MainActor in self?.showDiscoverTemplate() }
        }
        button.buttonStyle = .rounded
        return button
    }

    // MARK: - Discover

    private func showDiscoverTemplate() {
        let template = CPListTemplate(title: "Discover", sections: makeDiscoverSections())
        discoverTemplate = template
        pushTemplate(template, animated: true)
    }

    /// Mirrors the iPhone Discover page: Networks and Locations, then the four
    /// Browse by Interest options.
    private func makeDiscoverSections() -> [CPListSection] {
        let quick = [
            makeCategoryItem(.networks, subtitle: "Browse broadcasters", symbol: "dot.radiowaves.left.and.right"),
            makeCategoryItem(.locations, subtitle: "Cities, states and regions", symbol: "map")
        ]
        let interests = [
            makeCategoryItem(.music, subtitle: "Genres for every mood", symbol: "music.note"),
            makeDestinationItem(
                .genre(value: "News", title: "News and Talkback"),
                subtitle: "News, current affairs and conversation",
                image: symbolImage("bubble.left.and.text.bubble.right")
            ),
            makeDestinationItem(
                .genre(value: "Sport", title: "Sport"),
                subtitle: "Commentary, analysis and racing",
                image: symbolImage("sportscourt")
            ),
            makeCategoryItem(.specialist, subtitle: "Local voices and specialist services", symbol: "person.3.fill")
        ]
        return [
            CPListSection(items: quick),
            CPListSection(items: interests, header: "Browse by Interest", sectionIndexTitle: nil)
        ]
    }

    private func makeCategoryItem(_ category: BrowseCategory, subtitle: String, symbol: String) -> CPListItem {
        let item = CPListItem(
            text: category.title,
            detailText: subtitle,
            image: symbolImage(symbol),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { [weak self] _, completion in
            completion()
            Task { @MainActor in self?.showCategory(category) }
        }
        return item
    }

    private func showCategory(_ category: BrowseCategory) {
        selectedCategory = category
        let template = CPListTemplate(title: category.title, sections: makeCategorySections(category))
        applyLoadingEmptyState(template, emptyTitle: "Nothing to show")
        categoryTemplate = template
        pushTemplate(template, animated: true)
    }

    private func makeCategorySections(_ category: BrowseCategory) -> [CPListSection] {
        switch category {
        case .networks:
            let items = presenter.networks(from: player).map { network in
                makeDestinationItem(
                    .network(network),
                    subtitle: nil,
                    image: artworkProvider.placeholderImage(),
                    artworkURL: player.library.networkArtworkURL(for: network),
                    artworkBackground: network == "ARN" ? .black : .white
                )
            }
            return limitedSections([(nil, items)])
        case .locations:
            let national = makeDestinationItem(.national, subtitle: "Australia-wide stations", image: symbolImage("antenna.radiowaves.left.and.right"))
            let cities = DiscoverRegion.allCases.map {
                makeDestinationItem(.region($0), subtitle: nil, image: symbolImage($0.symbol))
            }
            let states = AustralianBroadcastState.allCases.map {
                makeDestinationItem(.state($0), subtitle: nil, image: symbolImage("map.fill"))
            }
            return limitedSections([(nil, [national]), ("Capital Cities", cities), ("Browse by State", states)])
        case .music:
            let items = presenter.musicGenres(from: player).map {
                makeDestinationItem(.genre(value: $0, title: $0), subtitle: nil, image: symbolImage("music.note.list"))
            }
            return limitedSections([(nil, items)])
        case .specialist:
            let items = presenter.specialistServices().map {
                makeDestinationItem(
                    .subnetwork(network: NetworkBrowseOrdering.specialist, value: $0.name),
                    subtitle: nil,
                    image: symbolImage($0.symbol)
                )
            }
            return limitedSections([(nil, items)])
        }
    }

    private func makeDestinationItem(
        _ destination: CarPlayStationDestination,
        subtitle: String?,
        image: UIImage?,
        artworkURL: URL? = nil,
        artworkBackground: UIColor = .white
    ) -> CPListItem {
        let count = presenter.stationCount(destination, from: player)
        let countText: String? = count > 0
            ? (count == 1 ? "1 station" : "\(count) stations")
            : (player.library.isLoading ? "Loading…" : nil)
        let detail = [subtitle, countText].compactMap { $0 }.joined(separator: " · ")
        let item = CPListItem(
            text: destination.title,
            detailText: detail.isEmpty ? nil : detail,
            image: image,
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { [weak self] _, completion in
            completion()
            Task { @MainActor in self?.showDestination(destination) }
        }
        if let artworkURL {
            Task { @MainActor [weak item, artworkProvider] in
                let image = await artworkProvider.image(for: artworkURL, background: artworkBackground)
                item?.setImage(image)
            }
        }
        return item
    }

    private func showDestination(_ destination: CarPlayStationDestination) {
        selectedDestination = destination
        let template = CPListTemplate(title: destination.title, sections: makeDestinationSections(destination))
        applyLoadingEmptyState(template, emptyTitle: "No stations found")
        destinationTemplate = template
        pushTemplate(template, animated: true)
    }

    private func makeDestinationSections(_ destination: CarPlayStationDestination) -> [CPListSection] {
        listSections(presenter.sections(destination, from: player))
    }

    private func applyLoadingEmptyState(_ template: CPListTemplate, emptyTitle: String) {
        let isLoading = player.library.isLoading
        template.emptyViewTitleVariants = [isLoading ? "Loading stations" : emptyTitle]
        if #available(iOS 18.4, *) {
            template.showsSpinnerWhileEmpty = isLoading
        }
    }

    private func symbolImage(_ name: String) -> UIImage? {
        UIImage(systemName: name)?.withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
    }

    // MARK: - Station rows

    private func listSections(_ sections: [CarPlayStationSection]) -> [CPListSection] {
        limitedSections(sections.map { section in
            (section.header, section.rows.map { makeStationItem(row: $0) })
        })
    }

    /// Applies CarPlay's per-list item limit across all sections, in order.
    private func limitedSections(_ sections: [(header: String?, items: [CPListItem])]) -> [CPListSection] {
        var remaining = Int(CPListTemplate.maximumItemCount)
        var result: [CPListSection] = []
        for section in sections where remaining > 0 && !section.items.isEmpty {
            let items = Array(section.items.prefix(remaining))
            remaining -= items.count
            result.append(CPListSection(items: items, header: section.header, sectionIndexTitle: nil))
        }
        return result
    }

    private func makeStationItem(row: CarPlayStationRow) -> CPListItem {
        let cached = artworkProvider.cachedImage(for: row.station)
        let item = CPListItem(
            text: row.title,
            detailText: row.detail,
            image: cached ?? artworkProvider.placeholderImage()
        )
        item.userInfo = row.id
        item.isPlaying = row.isCurrentStation
        item.playingIndicatorLocation = .trailing
        item.handler = { [weak self] _, completion in
            completion()
            Task { @MainActor in self?.play(row.station) }
        }

        if cached == nil {
            Task { @MainActor [weak item, artworkProvider] in
                let image = await artworkProvider.image(for: row.station)
                item?.setImage(image)
            }
        }
        return item
    }

    private func play(_ station: DirectoryStation) {
        if station.id != player.station.id || !player.requested {
            diagnose("carplay.play", "Station selected in CarPlay", metadata: ["stationID": station.id])
            player.playStation(station)
        }
        configureNowPlayingButtons()
        showNowPlayingRoot()
        refreshTemplates(force: true)
    }

    private func showNowPlayingRoot() {
        if rootRoute == .nowPlaying {
            popToRootTemplate()
        } else {
            rootRoute = .nowPlaying
            clearPushedTemplates()
            favouritesTemplate = nil
            setRootTemplate(CPNowPlayingTemplate.shared, animated: true)
        }
    }

    // MARK: - Now Playing

    private func configureNowPlayingTemplate() {
        let template = CPNowPlayingTemplate.shared
        template.remove(self)
        template.add(self)
        template.isUpNextButtonEnabled = true
        template.upNextTitle = "Favourites"
        template.isAlbumArtistButtonEnabled = false
        configureNowPlayingButtons()
    }

    private func configureNowPlayingButtons() {
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([makeFavouriteButton()])
    }

    private func makeFavouriteButton() -> CPNowPlayingImageButton {
        let isFavourite = player.hasDetails && player.library.contains(player.station)
        let image = UIImage(systemName: isFavourite ? "heart.fill" : "heart") ?? UIImage()
        let button = CPNowPlayingImageButton(image: image) { [weak self] _ in
            Task { @MainActor in self?.toggleFavourite() }
        }
        button.isEnabled = player.hasDetails
        button.isSelected = isFavourite
        return button
    }

    private func toggleFavourite() {
        guard player.hasDetails else { return }
        player.library.toggle(player.station)
        diagnose("carplay.favourite", "Favourite toggled in CarPlay", metadata: [
            "stationID": player.station.id,
            "favourite": "\(player.library.contains(player.station))"
        ])
        configureNowPlayingButtons()
        refreshTemplates(force: true)
    }

    // MARK: - Observation

    private func observePlayer() {
        cancellables.removeAll()
        Publishers.Merge(
            player.objectWillChange.map { _ in () },
            player.library.objectWillChange.map { _ in () }
        )
        .sink { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        .store(in: &cancellables)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.refreshTemplates(force: false)
        }
    }

    private func refreshTemplates(force: Bool) {
        let snapshot = Snapshot(player: player)
        guard force || snapshot != lastSnapshot else { return }
        let catalogueChanged = snapshot.catalogueCount != lastSnapshot?.catalogueCount
            || snapshot.isLoading != lastSnapshot?.isLoading
        lastSnapshot = snapshot

        favouritesTemplate?.updateSections(makeFavouriteSections())
        if catalogueChanged {
            discoverTemplate?.updateSections(makeDiscoverSections())
            if let selectedCategory, let categoryTemplate {
                categoryTemplate.updateSections(makeCategorySections(selectedCategory))
                applyLoadingEmptyState(categoryTemplate, emptyTitle: "Nothing to show")
            }
        }
        if let selectedDestination, let destinationTemplate {
            destinationTemplate.updateSections(makeDestinationSections(selectedDestination))
            applyLoadingEmptyState(destinationTemplate, emptyTitle: "No stations found")
        }
        configureNowPlayingButtons()

        // A station chosen on the iPhone while CarPlay shows the Favourites root
        // promotes Now Playing to the root, as Autohop does for its Up Next root.
        if rootRoute == .favourites, snapshot.hasStation, snapshot.isPlaying {
            rootRoute = .nowPlaying
            diagnose("carplay.root", "Switching to Now Playing root", metadata: ["stationID": snapshot.currentStationID])
            clearPushedTemplates()
            favouritesTemplate = nil
            setRootTemplate(CPNowPlayingTemplate.shared, animated: true)
        }
    }

    // MARK: - Template operations

    private func setRootTemplate(_ template: CPTemplate, animated: Bool) {
        interfaceController?.setRootTemplate(template, animated: animated) { [weak self] success, error in
            self?.logTemplateCompletion(operation: "rootTemplate", template: template, success: success, error: error)
        }
    }

    private func pushTemplate(_ template: CPTemplate, animated: Bool) {
        interfaceController?.pushTemplate(template, animated: animated) { [weak self] success, error in
            self?.logTemplateCompletion(operation: "pushTemplate", template: template, success: success, error: error)
        }
    }

    private func popToRootTemplate() {
        interfaceController?.popToRootTemplate(animated: true) { [weak self] success, error in
            self?.logTemplateCompletion(operation: "popToRootTemplate", template: nil, success: success, error: error)
        }
    }

    private func logTemplateCompletion(
        operation: String,
        template: CPTemplate?,
        success: Bool,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.diagnose("carplay.templateFailed", "CarPlay rejected template operation", metadata: [
                "operation": operation,
                "template": template.map { String(describing: type(of: $0)) } ?? "none",
                "success": "\(success)",
                "error": error.localizedDescription
            ])
        }
    }

    private func diagnose(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        StreamDiagnosticLogger.shared.record(event, message, metadata: metadata)
    }
}

extension CarPlayCoordinator: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor [weak self] in
            self?.showFavouritesTemplate()
        }
    }
}
