import Foundation

// ============================================================================
// AI CONTEXT - CarPlay/CarPlayStationPresenter.swift
//
// PURPOSE: Read-only projection from Wireless's StationLibrary and MobilePlayer
// into the small row models used by CarPlay list templates. Adapted from
// Autohop's CarPlayEpisodePresenter so the template code never needs to know
// how favourites, recents or the Discover categories are filtered and ordered.
// Every filter here must match the iPhone Discover page (DiscoverView,
// DiscoverFacetView, NetworkSubnetworkView and RadioPlayerView's routes).
// ============================================================================

struct CarPlayStationRow: Identifiable, Equatable {
    let id: String
    let station: DirectoryStation
    let title: String
    let detail: String?
    let isCurrentStation: Bool
}

struct CarPlayStationSection {
    let header: String?
    let rows: [CarPlayStationRow]
}

/// A Discover destination that ends in a list of stations.
enum CarPlayStationDestination: Equatable {
    case national
    case region(DiscoverRegion)
    case state(AustralianBroadcastState)
    case network(String)
    case subnetwork(network: String, value: String)
    case genre(value: String, title: String)

    var title: String {
        switch self {
        case .national: return "National"
        case .region(let region): return region.rawValue
        case .state(let state): return state.shortTitle
        case .network(let network): return MajorNetworkCatalogue.displayName(for: network)
        case .subnetwork(_, let value): return value
        case .genre(_, let title): return title
        }
    }
}

@MainActor
struct CarPlayStationPresenter {
    func favouriteRows(from player: MobilePlayer) -> [CarPlayStationRow] {
        rows(player.library.favourites, player: player)
    }

    func recentRows(from player: MobilePlayer) -> [CarPlayStationRow] {
        rows(player.library.recents, player: player)
    }

    // MARK: Discover categories

    /// Matches the iPhone Networks page's highlighted major networks
    /// (MajorNetworkCatalogue), in the same display-name order, limited to
    /// networks present in the current directory.
    func networks(from player: MobilePlayer) -> [String] {
        let available = Set(player.library.networks)
        return MajorNetworkCatalogue.all.map(\.directoryName).filter { available.contains($0) }
    }

    /// Matches DiscoverFacetView(kind: .genres).
    func musicGenres(from player: MobilePlayer) -> [String] {
        player.library.musicGenres.filter { $0 != "News" && $0 != "Sport" }
    }

    func specialistServices() -> [NetworkSubnetwork] {
        NetworkSubnetworkCatalogue.services(for: NetworkBrowseOrdering.specialist) ?? []
    }

    func stationCount(_ destination: CarPlayStationDestination, from player: MobilePlayer) -> Int {
        stations(destination, from: player).count
    }

    // MARK: Station lists

    func sections(_ destination: CarPlayStationDestination, from player: MobilePlayer) -> [CarPlayStationSection] {
        // CarPlay limits navigation depth, so a network with services (ABC,
        // Triple M and so on) shows its stations grouped by service on one
        // list instead of the iPhone's extra service page.
        if case .network(let network) = destination,
           let services = NetworkSubnetworkCatalogue.services(for: network) {
            let all = stations(destination, from: player)
            var grouped = services.map { service in
                CarPlayStationSection(
                    header: service.name,
                    rows: rows(stations(.subnetwork(network: network, value: service.name), from: player), player: player)
                )
            }
            let listed = Set(grouped.flatMap { $0.rows.map(\.id) })
            let others = all.filter { !listed.contains($0.id) }
            if !others.isEmpty {
                grouped.append(CarPlayStationSection(header: "Other", rows: rows(others, player: player)))
            }
            return grouped.filter { !$0.rows.isEmpty }
        }
        return [CarPlayStationSection(header: nil, rows: rows(stations(destination, from: player), player: player))]
    }

    private func stations(_ destination: CarPlayStationDestination, from player: MobilePlayer) -> [DirectoryStation] {
        let library = player.library
        switch destination {
        case .national:
            return library.results(favouritesOnly: false, query: "", network: "", city: "", state: "National")
        case .region(let region):
            return DiscoverRegions.stations(library.stations, in: region)
        case .state(let state):
            return library.results(favouritesOnly: false, query: "", network: "", city: "", state: state.rawValue)
        case .network(let network):
            return library.results(favouritesOnly: false, query: "", network: network, city: "")
        case .subnetwork(let network, let value):
            return library.results(favouritesOnly: false, query: "", network: network, city: "", subnetwork: value)
        case .genre(let value, _):
            return library.results(favouritesOnly: false, query: "", network: "", city: "", musicGenre: value)
        }
    }

    private func rows(_ stations: [DirectoryStation], player: MobilePlayer) -> [CarPlayStationRow] {
        stations
            .filter { $0.preferredStream != nil }
            .map { station in
                CarPlayStationRow(
                    id: station.id,
                    station: station,
                    title: station.name,
                    detail: detail(for: station),
                    isCurrentStation: station.id == player.station.id && player.requested
                )
            }
    }

    private func detail(for station: DirectoryStation) -> String? {
        let parts = [station.frequency, station.location.isEmpty ? nil : station.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? (station.network.isEmpty ? nil : station.network) : parts.joined(separator: " · ")
    }
}
