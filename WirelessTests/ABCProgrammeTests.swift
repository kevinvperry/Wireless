import XCTest
import Combine

final class ABCProgrammeTests: XCTestCase {
    func testParsesPresentersAndAbsoluteTimesWithoutTrustingCachedOnNow() throws {
        let data = Data(#"""
        {"formattedScheduleArray":[{"timeBlockTitle":"Early"},{"items":[
          {"id":"repeat","title":" Overnight programme ","rawStartTime":"2026-10-24T23:00:00+11:00","rawEndTime":"2026-10-25T02:00:00.000+11:00","onNow":false,"presenters":[{"displayName":" Presenter One "},{"displayName":"Presenter Two"}]},
          {"id":"repeat","title":"Later broadcast","rawStartTime":"2026-10-25T23:00:00+11:00","rawEndTime":"2026-10-26T02:00:00+11:00"}
        ]}]}
        """#.utf8)
        let programmes = try ABCProgrammeParser.parse(data, serviceID: "LOCAL_MELBOURNE")
        XCTAssertEqual(programmes.count, 2)
        XCTAssertEqual(programmes[0].name, "Overnight programme")
        XCTAssertEqual(programmes[0].presenter, "Presenter One, Presenter Two")
        XCTAssertEqual(programmes[0].end.timeIntervalSince(programmes[0].start), 3 * 3600)
        XCTAssertEqual(programmes[0].start, ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z"))
        XCTAssertNotEqual(programmes[0].id, programmes[1].id)
        XCTAssertNil(programmes[1].presenter)
    }

    func testEmptySportBlocksAndIncompleteEntriesDoNotInventProgrammes() throws {
        let data = Data(#"""
        {"formattedScheduleArray":[{}, {"items":[
          {"title":"No times"},
          {"title":"Backwards","rawStartTime":"2026-10-25T02:00:00Z","rawEndTime":"2026-10-25T01:00:00Z"},
          {"title":"  ","rawStartTime":"2026-10-25T01:00:00Z","rawEndTime":"2026-10-25T02:00:00Z"}
        ]}]}
        """#.utf8)
        XCTAssertTrue(try ABCProgrammeParser.parse(data, serviceID: "ITINERANT_ONE").isEmpty)
        XCTAssertThrowsError(try ABCProgrammeParser.parse(Data("{}".utf8), serviceID: "RN"))
        XCTAssertThrowsError(try ABCProgrammeParser.parse(Data("null".utf8), serviceID: "RN"))
    }

    @MainActor
    func testEasternRNFallbackLoadsCurrentAndUpcomingAcrossMidnight() async {
        let instant = ISO8601DateFormatter().date(from: "2026-10-25T00:00:00Z")!
        let guide = ProgrammeGuide(loader: { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "tz" }?.value, "UTC")
            let service = query.first { $0.name == "service" }!.value!
            let body = service == "RN" ? #"""
            {"formattedScheduleArray":[{"items":[
              {"id":"overnight","title":"Overnight","rawStartTime":"2026-10-24T23:00:00Z","rawEndTime":"2026-10-25T01:00:00Z"},
              {"id":"next","title":"Next programme","rawStartTime":"2026-10-25T01:00:00Z","rawEndTime":"2026-10-25T02:00:00Z"}
            ]}]}
            """# : #"{"formattedScheduleArray":[]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, now: { instant })
        let loaded = expectation(description: "Current national eastern programme")
        let subscription = guide.$current.compactMap { $0 }.prefix(1).sink { programme in
            XCTAssertEqual(programme.name, "Overnight")
            loaded.fulfill()
        }
        guide.startABC(serviceID: "RN_VIC")
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(guide.upcoming.map(\.name), ["Next programme"])
        guide.stop()
        XCTAssertNil(guide.current)
        XCTAssertTrue(guide.upcoming.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testRegionalAndEventMappingsUseOfficialIdentifiers() {
        func station(_ id: String, network: String = "ABC") -> DirectoryStation {
            DirectoryStation(id: id, name: "Name may change", network: network, country: "AU", state: "", cities: [], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])
        }
        XCTAssertEqual(station("station_0eddffb877dd").abcProgrammeServiceID, "LOCAL_NORTHWESTWA")
        XCTAssertEqual(station("station_7f296c08035f").abcProgrammeServiceID, "LOCAL_WESTERNVIC")
        XCTAssertEqual(station("station_7979e56607a5").abcProgrammeServiceID, "RN_WA")
        XCTAssertEqual(station("station_55386dde3229").abcProgrammeServiceID, "ABCSPORTSYNC")
        XCTAssertNil(station("station_7979e56607a5", network: "Other").abcProgrammeServiceID)
        XCTAssertNil(station("station_bc8eb207c4f2").abcProgrammeServiceID) // Double J keeps songs.
    }
}
