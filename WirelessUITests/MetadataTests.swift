import XCTest

final class MetadataTests: XCTestCase {
    @MainActor
    func testSongAndTemporaryUnfilteredAssetMetadataStayAboveStation() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_METADATA_PREVIEW"] = "1"
        app.launch()
        let title = app.staticTexts["currentTrackTitle"]
        let station = app.staticTexts["playerSecondaryTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Never Tear Us Apart · INXS")
        XCTAssertEqual(station.label, "Triple M Melbourne 105.1")
        XCTAssertLessThan(title.frame.maxY, station.frame.minY)
        capture(app, "Song above station")

        app.buttons["Commercial break"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Asset Stop 00:00 2026-10-14T07:59:59.918Z · Asset Stop 00:00 2026-10-14T07:59:59.918Z")
        XCTAssertEqual(station.label, "Triple M Melbourne 105.1")
        XCTAssertLessThan(title.frame.maxY, station.frame.minY)
        capture(app, "Asset metadata displayed")

        app.buttons["Resume song"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Never Tear Us Apart · INXS")
        XCTAssertEqual(station.label, "Triple M Melbourne 105.1")
        XCTAssertLessThan(title.frame.maxY, station.frame.minY)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
