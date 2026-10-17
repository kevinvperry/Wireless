import Foundation

struct StationListSection: Identifiable, Equatable {
    let title: String
    let stations: [DirectoryStation]

    var id: String { title }
}

enum StationListOrganisation {
    /// Breakfast ratings supplied for the 15 October 2026 directory update,
    /// ordered by the current audience-share result in descending order.
    private static let topRatingStationIDsByCity = [
        "Sydney": [
            "station_2a1af692c272", // Smooth FM 95.3
            "station_44dd138bd4c1", // 2GB
            "station_2bef6affd01d", // Nova 96.9
            "station_78faec2ef9b7", // GOLD101.7
            "station_adc3aa7bbe77", // KIIS 1065
            "station_285185e82eeb", // Triple M Sydney 104.9
            "station_11264c4bac29", // ABC Sydney
            "station_773825606c43", // 2DayFM 104.1 Sydney
            "station_44be1ee32ff3", // 2UE
            "station_fa56bb0deca5", // Sky Sports Radio
            "station_612f55de42a8"  // SEN 1170
        ],
        "Melbourne": [
            "station_47cd29da5a1d", // 3AW Melbourne
            "station_dbbb4ad7c472", // GOLD104.3
            "station_57fa9c360020", // Smooth FM 91.5
            "station_33b5c26fda71", // The Fox Melbourne
            "station_5d842ee95e32", // Nova 100
            "station_89605657cb78", // Triple M Melbourne 105.1
            "station_f9e327bf23a1", // ABC Melbourne
            "station_dd86393c13d8", // KIIS 1011
            "station_62d2e55ae9ff", // SEN 1116
            "station_2e730d7af3cb", // Magic 1278
            "station_de2e44c4f0a8"  // 3MP
        ],
        "Brisbane": [
            "station_7769426de525", // Triple M Brisbane 104.5
            "station_5dd9ed2d5c6f", // 4BH
            "station_8c7ad1d3da5f", // B105 Brisbane
            "station_c6c15fd1586f", // KIIS 973
            "station_7f4a6f6ff529", // Nova 106.9
            "station_53134d345305", // ABC Brisbane
            "station_db432bcf4c61", // 4BC Brisbane
            "station_7ea2e37443b4"  // SENQ
        ],
        "Adelaide": [
            "station_1f72e1b25208", // Triple M Adelaide 104.7 (5MMM)
            "station_e203995c549d", // Nova 919
            "station_66c6f546c81c", // SAFM Adelaide
            "station_55b73ef16c0d", // KIIS 1023
            "station_78ff85cace99", // FIVEAA
            "station_7de64417a171", // ABC Adelaide
            "station_398cd83cda2e"  // GOLD1323 (CRUISE1323 in ratings chart)
        ],
        "Perth": [
            "station_cae7a9815bba", // Nova 93.7
            "station_b8bbb3631e74", // Triple M Perth 92.9
            "station_cf0ceecd6c57", // Mix94.5 Perth
            "station_b9975bdb69f2", // GOLD 96FM
            "station_3f29cc24820d", // 6PR Perth
            "station_31d448ef0a80", // 6iX
            "station_1b89f545bcf2"  // ABC Perth
        ]
    ]

    static func topRatingStations(for city: String, from stations: [DirectoryStation]) -> [DirectoryStation] {
        let stationsByID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        return (topRatingStationIDsByCity[city] ?? []).compactMap { stationsByID[$0] }
    }

    static func excludingTopRatings(for city: String, from stations: [DirectoryStation]) -> [DirectoryStation] {
        let topIDs = Set(topRatingStationIDsByCity[city] ?? [])
        return stations.filter { !topIDs.contains($0.id) }
    }

    static func alphabeticalSections(from stations: [DirectoryStation]) -> [StationListSection] {
        let sorted = stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let grouped = Dictionary(grouping: sorted) { station in
            guard let scalar = station.name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first,
                  CharacterSet.letters.contains(scalar) else { return "#" }
            return String(scalar).uppercased()
        }
        let titles = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return titles.map { StationListSection(title: $0, stations: grouped[$0] ?? []) }
    }
}
