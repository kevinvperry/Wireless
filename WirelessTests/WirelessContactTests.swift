import XCTest

final class WirelessContactTests: XCTestCase {
    func testGeneralContactURLIdentifiesWireless() throws {
        let components = try XCTUnwrap(URLComponents(url: WirelessContact.generalURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "kevmarl.com")
        XCTAssertEqual(components.path, "/contact")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "product" })?.value, "Wireless")
    }

    func testStationReportIncludesDirectoryIdentityAndConcernTypes() throws {
        let station = DirectoryStation(
            id: "station-test", name: "Example FM", network: "Example Network",
            country: "AU", state: "VIC", cities: ["Melbourne"], tags: [],
            description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: []
        )
        let components = try XCTUnwrap(URLComponents(url: WirelessContact.stationIssueURL(for: station), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["topic"], "station-report")
        XCTAssertEqual(items["station_name"], "Example FM")
        XCTAssertEqual(items["station_id"], "station-test")
        XCTAssertEqual(items["network"], "Example Network")
        XCTAssertEqual(items["issue_types"], "technical,directory,ownership,legal")
    }
}
