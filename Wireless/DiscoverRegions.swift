import Foundation

/// Mobile-only browsing policy. Flagship IDs and order come from
/// research/australian-radio/capital-cities.md and its companion JSON (10 October 2026).
enum DiscoverRegion: String, CaseIterable, Identifiable, Hashable {
    case melbourne = "Melbourne"
    case sydney = "Sydney"
    case brisbane = "Brisbane"
    case adelaide = "Adelaide"
    case perth = "Perth"
    case hobart = "Hobart"
    case canberra = "Canberra"
    case darwin = "Darwin"
    var id: String { rawValue }
    var symbol: String { "building.2" }
}

enum AustralianBroadcastState: String, CaseIterable, Identifiable, Hashable {
    case act = "Australian Capital Territory"
    case nsw = "New South Wales"
    case nt = "Northern Territory"
    case queensland = "Queensland"
    case sa = "South Australia"
    case tasmania = "Tasmania"
    case victoria = "Victoria"
    case wa = "Western Australia"

    var id: String { rawValue }
    var shortTitle: String {
        switch self {
        case .act: return "ACT"
        case .nsw: return "New South Wales"
        case .nt: return "Northern Territory"
        case .queensland: return "Queensland"
        case .sa: return "South Australia"
        case .tasmania: return "Tasmania"
        case .victoria: return "Victoria"
        case .wa: return "Western Australia"
        }
    }
}

enum DiscoverRegions {
    static let flagships: [DiscoverRegion: [String]] = [
        .melbourne: ["station_f9e327bf23a1", "station_62d2e55ae9ff", "station_33b5c26fda71", "station_89605657cb78", "station_5d842ee95e32", "station_57fa9c360020", "station_dd86393c13d8", "station_dbbb4ad7c472", "station_47cd29da5a1d"],
        .sydney: ["station_11264c4bac29", "station_612f55de42a8", "station_773825606c43", "station_285185e82eeb", "station_2bef6affd01d", "station_2a1af692c272", "station_adc3aa7bbe77", "station_78faec2ef9b7", "station_44dd138bd4c1"],
        .brisbane: ["station_53134d345305", "station_7ea2e37443b4", "station_8c7ad1d3da5f", "station_7769426de525", "station_7f4a6f6ff529", "station_3c149ef44a68", "station_c6c15fd1586f", "station_d09424bfbfac", "station_db432bcf4c61"],
        .adelaide: ["station_7de64417a171", "station_ce7d49d13fcb", "station_66c6f546c81c", "station_1f72e1b25208", "station_e203995c549d", "station_a876171726ed", "station_55b73ef16c0d", "station_398cd83cda2e"],
        .perth: ["station_1b89f545bcf2", "station_b94a294d47ae", "station_cf0ceecd6c57", "station_b8bbb3631e74", "station_cae7a9815bba", "station_e3ef9b098113", "station_5f07222bd20d", "station_b9975bdb69f2", "station_3f29cc24820d"],
        .hobart: ["station_d1fe63732c57", "station_c0decfdb0d7a", "station_035905e85af3", "station_bc93a726d80e"],
        .canberra: ["station_15e980155375", "station_6e88b935dc42", "station_76e630802468"],
        .darwin: ["station_941a34adbebd", "station_3b78fdea2a3d"],
    ]
    static let networks = ["ABC", "SEN", "Hit Network", "Triple M", "Nova", "Smooth", "KIIS", "Gold", "Talk radio"]

    static func regions(for station: DirectoryStation) -> [DiscoverRegion] {
        let curated = DiscoverRegion.allCases.filter { flagships[$0]?.contains(station.id) == true }
        if !curated.isEmpty { return curated }
        return DiscoverRegion.allCases.filter { region in
            station.cities.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(region.rawValue) == .orderedSame
            }
        }
    }

    static func stations(_ stations: [DirectoryStation], in region: DiscoverRegion) -> [DirectoryStation] {
        stations.filter { regions(for: $0).contains(region) }.sorted {
            let left = rank($0, in: region), right = rank($1, in: region)
            if left != right { return left < right }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
    static func rank(_ station: DirectoryStation, in region: DiscoverRegion) -> Int {
        if let index = flagships[region]?.firstIndex(of: station.id) { return index }
        if let index = networks.firstIndex(of: station.network) { return 100 + index }
        if ["SBS", "SBS Audio"].contains(station.network) { return 120 }
        return 1000
    }
}
