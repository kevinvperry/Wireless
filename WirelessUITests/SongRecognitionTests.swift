import XCTest

final class SongRecognitionUITests: XCTestCase {
    @MainActor func testResultAndFailureLayouts() { checkLayouts(largeText: false) }
    @MainActor func testAccessibilityResultLayout() { checkLayouts(largeText: true, modes: ["found"]) }
    @MainActor private func checkLayouts(largeText: Bool, modes: [String] = ["found", "no-match", "error", "listening"]) {
        for mode in modes {
            let app = XCUIApplication()
            app.launchEnvironment["WIRELESS_SONG_PREVIEW"] = mode
            if largeText {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            XCTAssertTrue(app.navigationBars["Identify song"].waitForExistence(timeout: 10))
            if mode == "found" {
                XCTAssertTrue(app.staticTexts["identifiedSongTitle"].waitForExistence(timeout: 5))
                // Scrollable content keeps actions reachable at accessibility sizes.
                let save = app.buttons["Save to Shazam"]
                for _ in 0..<4 { if save.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(save.isHittable)
                XCTAssertTrue(app.buttons["Open in Apple Music"].exists || app.links["Open in Apple Music"].exists)
            } else if mode == "listening" {
                XCTAssertTrue(app.buttons["Cancel identification"].exists)
            } else {
                XCTAssertTrue(app.buttons["Identify again"].exists)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Song recognition \(mode)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    @MainActor func testSilentLiveCaptureFallsBackWithoutStoppingPlayback() throws {
        try checkPlayback(format: "hls", silentSource: true)
    }
    @MainActor func testHLSDeepBassPlaybackCanIdentifyWithoutStoppingPlayback() throws {
        try checkPlayback(format: "hls", musicPreset: "deep")
    }
    @MainActor func testHLSSamplesCurrentPlayerWithoutStoppingPlayback() throws {
        try checkPlayback(format: "hls")
    }
    @MainActor func testIdentifySamplesWithoutStoppingPlaybackAndCanBeClosed() throws {
        try checkPlayback(format: "aac")
    }
    @MainActor private func checkPlayback(format: String, musicPreset: String? = nil, silentSource: Bool = false) throws {
        // Optional integration fixture; the normal suite remains self-contained.
        let probe = URL(string: "http://127.0.0.1:18742/tone.aac")!
        guard let bytes = try? Data(contentsOf: probe), !bytes.isEmpty else {
            throw XCTSkip("Start the local generated audio fixture on port 18742 for playback integration checks")
        }
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launchEnvironment["WIRELESS_TEST_MUSIC_PRESET"] = musicPreset
        app.launchEnvironment["WIRELESS_TEST_SILENT_SONG_SOURCE"] = silentSource ? "1" : nil
        app.launchEnvironment["WIRELESS_TEST_HLS_URL"] = "http://127.0.0.1:18742/tone.\(format == "hls" ? "m3u8" : "aac")"
        app.launchEnvironment["WIRELESS_TEST_STREAM_FORMAT"] = format
        app.launchArguments = ["-streamDiagnosticLoggingEnabled", "YES"]
        app.launch()
        let identify = app.buttons["identifySongButton"]
        XCTAssertTrue(identify.waitForExistence(timeout: 15))
        XCTAssertFalse(identify.isEnabled)
        app.buttons["Play"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: identify)
        waitForExpectations(timeout: 20)
        let playerShot = XCTAttachment(screenshot: app.screenshot())
        playerShot.name = "Identify song player"; playerShot.lifetime = .keepAlways; add(playerShot)
        // Let the fixture's existing sound-processing fallback settle before
        // testing recognition. Some simulator runtimes never activate HLS taps.
        if musicPreset != nil { Thread.sleep(forTimeInterval: 8) }
        identify.tap()
        XCTAssertTrue(app.navigationBars["Identify song"].waitForExistence(timeout: 5))
        if silentSource {
            let explanation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Identifying from a separate connection")).firstMatch
            XCTAssertTrue(explanation.waitForExistence(timeout: 8))
        }
        if format == "hls" {
            let submitted = NSPredicate { _, _ in
                app.staticTexts["Checking with Shazam…"].exists
                    || app.staticTexts["No song found"].exists
                    || app.staticTexts["Shazam could not complete the request. Check your internet connection and try again."].exists
            }
            expectation(for: submitted, evaluatedWith: app)
            waitForExpectations(timeout: 20)
        }
        XCTAssertTrue(app.staticTexts["songRecognitionProgress"].waitForExistence(timeout: 5)
                      || app.staticTexts["Unable to identify"].exists || app.staticTexts["No song found"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Identify song sheet"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(identify.isEnabled)
        identify.tap()
        XCTAssertTrue(app.navigationBars["Identify song"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertFalse(identify.isEnabled)
    }
}
