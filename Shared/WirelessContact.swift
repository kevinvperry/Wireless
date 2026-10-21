import Foundation

enum WirelessContact {
    private static let contactPage = URL(string: "https://kevmarl.com/contact")!

    static var generalURL: URL {
        contactURL(queryItems: [
            URLQueryItem(name: "product", value: "Wireless")
        ])
    }

    static func stationIssueURL(for station: DirectoryStation) -> URL {
        contactURL(queryItems: [
            URLQueryItem(name: "product", value: "Wireless"),
            URLQueryItem(name: "topic", value: "station-report"),
            URLQueryItem(name: "station_name", value: station.name),
            URLQueryItem(name: "station_id", value: station.id),
            URLQueryItem(name: "network", value: station.network),
            URLQueryItem(name: "issue_types", value: "technical,directory,ownership,legal")
        ])
    }

    private static func contactURL(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: contactPage, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}
