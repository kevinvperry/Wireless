import XCTest

final class PlayerTests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            let visible = app.frame.insetBy(dx: 12, dy: 110)
            if element.isHittable, visible.contains(element.frame) { return }
            if element.frame.minY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
    }

    @MainActor
    func testAudioControlsCardLayout() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launchArguments = ProcessInfo.processInfo.environment["WIRELESS_TEST_LARGE_TEXT"] == "1"
            ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        let bass = app.buttons["Pop & R&B"]
        XCTAssertTrue(bass.waitForExistence(timeout: 5))
        reveal(bass, in: app)
        XCTAssertTrue(bass.isHittable)
        var shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Audio Controls music"; shot.lifetime = .keepAlways; add(shot)
        let vocal = app.descendants(matching: .any)["vocalBoostPicker"].firstMatch
        reveal(vocal, in: app)
        XCTAssertTrue(vocal.isHittable)
        shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Audio Controls voices"; shot.lifetime = .keepAlways; add(shot)
        let stream = app.descendants(matching: .any)["streamPicker"].firstMatch
        reveal(stream, in: app)
        XCTAssertTrue(stream.isHittable)
        if app.frame.width > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(stream, in: app)
            XCTAssertTrue(stream.isHittable)
            shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Audio Controls landscape"; shot.lifetime = .keepAlways; add(shot)
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testRepeatedSoundChangesKeepLivePlaybackRunning() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launchEnvironment["WIRELESS_TEST_HLS_URL"] = ProcessInfo.processInfo.environment["WIRELESS_TEST_HLS_URL"]
        app.launchEnvironment["WIRELESS_TEST_STREAM_FORMAT"] = ProcessInfo.processInfo.environment["WIRELESS_TEST_STREAM_FORMAT"]
        app.launchArguments = ["-streamDiagnosticLoggingEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        let vocal = app.segmentedControls["vocalBoostPicker"]
        reveal(vocal, in: app)
        vocal.buttons["Standard"].tap()
        app.buttons["Close"].tap()
        app.buttons["Play"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 40)
        app.buttons["Audio Controls"].tap()
        let vocalState = app.staticTexts["vocalBoostStatus"]
        let bassState = app.staticTexts["deepBassStatus"]
        let bass = app.otherElements["musicPresetPicker"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Active ·"), evaluatedWith: vocalState)
        waitForExpectations(timeout: 30)
        for _ in 0..<3 {
            reveal(vocal, in: app)
            for level in ["Light", "Strong", "Standard", "Off"] { vocal.buttons[level].tap() }
            reveal(bass, in: app)
            for level in ["Mid Bass", "Deep Bass", "Pop & R&B", "Off"] {
                reveal(bass.buttons[level], in: app)
                bass.buttons[level].tap()
                XCTAssertTrue(bass.buttons[level].isSelected)
                if level == "Pop & R&B" {
                    expectation(for: NSPredicate(format: "label CONTAINS %@", "Active · Pop & R&B"), evaluatedWith: bassState)
                    waitForExpectations(timeout: 10)
                    let shot = XCTAttachment(screenshot: app.screenshot())
                    shot.name = "Active Pop and RnB"; shot.lifetime = .keepAlways; add(shot)
                }
            }
            XCTAssertTrue(bassState.label.hasPrefix("Off ·"))
            app.buttons["Close"].tap()
            XCTAssertEqual(app.staticTexts["playbackStatus"].label, "Playing")
            app.buttons["Audio Controls"].tap()
        }
        reveal(vocal, in: app)
        vocal.buttons["Strong"].tap()
        XCTAssertTrue(vocal.buttons["Strong"].isSelected, "Final speech preset must actually be selected")
        let selectedShot = XCTAttachment(screenshot: app.screenshot())
        selectedShot.name = "Final Strong selection"; selectedShot.lifetime = .keepAlways; add(selectedShot)
        // Give a stopped render graph enough time to lose its Active state.
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(vocalState.label.contains("Active ·"), vocalState.label)
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["Close"].tap()
        app.buttons["Pause"].tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["Play"].exists)
    }

    @MainActor
    func testDeepBassAvailabilityAndExclusiveSelection() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        let vocal = app.segmentedControls["vocalBoostPicker"]
        reveal(vocal, in: app)
        vocal.buttons["Strong"].tap()
        let bass = app.otherElements["musicPresetPicker"]
        reveal(bass, in: app)
        XCTAssertTrue(bass.waitForExistence(timeout: 5))
        reveal(bass, in: app)
        bass.buttons["Deep Bass"].tap()
        let status = app.staticTexts["deepBassStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        if #available(iOS 27.0, *) {
            XCTAssertTrue(status.label.contains("Ready · Press Play to use Deep Bass"), status.label)
        } else {
            XCTAssertTrue(status.label.contains("HLS Deep Bass requires iOS 27"), status.label)
        }
        XCTAssertTrue(vocal.buttons["Off"].isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Deep Bass availability"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Close"].tap()
        app.terminate()
        app.launchEnvironment["WIRELESS_PRESERVE_PREVIEW_DEFAULTS"] = "1"
        app.launch()
        app.buttons["Audio Controls"].tap()
        XCTAssertTrue(bass.buttons["Deep Bass"].isSelected, "Deep Bass should survive an app restart")
        reveal(bass.buttons["Pop & R&B"], in: app)
        bass.buttons["Pop & R&B"].tap()
        app.buttons["Close"].tap()
        app.terminate(); app.launch()
        app.buttons["Audio Controls"].tap()
        XCTAssertTrue(bass.buttons["Pop & R&B"].isSelected, "Pop & R&B should survive an app restart")
        // Selecting speech restores the mutually exclusive preset in both directions.
        reveal(vocal, in: app)
        vocal.buttons["Light"].tap()
        XCTAssertTrue(bass.buttons["Off"].isSelected)
        reveal(bass, in: app)
        bass.buttons["Deep Bass"].tap()
        app.buttons["Close"].tap()
        app.buttons["Sync"].tap()
        let sync = app.switches["syncEnabled"]
        expectation(for: NSPredicate { _, _ in
            sync.isHittable && sync.frame.minX >= 0 && sync.frame.maxX <= app.frame.maxX
        }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        sync.tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: sync)
        waitForExpectations(timeout: 5)
        app.buttons["Playing"].tap()
        let audio = app.buttons["Audio Controls"]
        expectation(for: NSPredicate { _, _ in audio.isHittable && audio.frame.minX >= 0 }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        audio.tap()
        XCTAssertTrue(bass.waitForExistence(timeout: 5))
        XCTAssertFalse(bass.buttons["Pop & R&B"].isEnabled)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Unavailable while TV Sync is on"))
    }

    @MainActor
    func testLiveHLSDeepBassAndOff() {
        guard #available(iOS 27.0, *) else { return }
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launchArguments = ["-streamDiagnosticLoggingEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        let bass = app.otherElements["musicPresetPicker"]
        reveal(bass, in: app)
        bass.buttons["Deep Bass"].tap()
        app.buttons["Close"].tap()
        app.buttons["Play"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 35)
        app.buttons["Audio Controls"].tap()
        let status = app.staticTexts["deepBassStatus"]
        if !status.isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Active · Bass enhancement"), evaluatedWith: status)
        waitForExpectations(timeout: 25)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Live HLS Deep Bass"; shot.lifetime = .keepAlways; add(shot)
        reveal(bass, in: app)
        bass.buttons["Off"].tap()
        XCTAssertTrue(status.label.hasPrefix("Off ·"))
        app.buttons["Close"].tap()
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 20)
        app.buttons["Pause"].tap()
    }

    @MainActor
    func testLiveHLSVocalBoostBecomesActive() {
        guard #available(iOS 27.0, *) else { return }
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launchEnvironment["WIRELESS_TEST_HLS_URL"] = ProcessInfo.processInfo.environment["WIRELESS_TEST_HLS_URL"]
        app.launchArguments = ["-streamDiagnosticLoggingEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        reveal(app.segmentedControls["vocalBoostPicker"], in: app)
        app.segmentedControls["vocalBoostPicker"].buttons["Standard"].tap()
        app.buttons["Close"].tap()
        app.buttons["Play"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 35)
        app.buttons["Audio Controls"].tap()
        let status = app.staticTexts["vocalBoostStatus"]
        let active = NSPredicate(format: "label CONTAINS %@", "Active ·")
        expectation(for: active, evaluatedWith: status)
        waitForExpectations(timeout: 25)
        app.segmentedControls["vocalBoostPicker"].buttons["Strong"].tap()
        XCTAssertTrue(status.label.contains("Active ·"), "Changing an active boost level should preserve processed playback")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Live HLS Vocal Boost"; shot.lifetime = .keepAlways; add(shot)
        app.segmentedControls["vocalBoostPicker"].buttons["Off"].tap()
        XCTAssertTrue(status.label.contains("Original broadcast audio"))
        app.buttons["Close"].tap()
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 20)
        app.buttons["Pause"].tap()
    }

    @MainActor
    func testVocalBoostExplainsActualAvailability() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 15))
        app.buttons["Audio Controls"].tap()
        let picker = app.segmentedControls["vocalBoostPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        reveal(picker, in: app)
        picker.buttons["Standard"].tap()
        let status = app.staticTexts["vocalBoostStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        if #available(iOS 27.0, *) {
            XCTAssertTrue(status.label.contains("Ready"), status.label)
        } else {
            XCTAssertTrue(status.label.contains("requires iOS 27"), status.label)
            XCTAssertTrue(status.label.contains("Unavailable"), status.label)
        }
        XCTAssertFalse(status.label.contains("Active ·"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Vocal Boost availability"; shot.lifetime = .keepAlways; add(shot)
        picker.buttons["Off"].tap()
        XCTAssertTrue(status.label.contains("Original broadcast audio"))
    }

    @MainActor
    func testPopulatedAdaptivePlayerLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_PLAYER_PREVIEW"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let audio = app.buttons["Audio Controls"]
        XCTAssertTrue(audio.waitForExistence(timeout: 15))
        let route = app.descendants(matching: .any)["audioSourceSelector"].firstMatch
        XCTAssertTrue(route.exists)
        if app.frame.width >= 368 {
            XCTAssertEqual(audio.frame.midY, route.frame.midY, accuracy: 2)
        }
        let favourite = app.buttons["favouriteShortcut-layout-favourite"]
        XCTAssertTrue(favourite.isHittable)
        XCTAssertLessThanOrEqual(favourite.frame.height, 80)
        XCTAssertLessThan(favourite.frame.maxY, app.frame.maxY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Populated portrait player"; shot.lifetime = .keepAlways; add(shot)
        if app.frame.width >= 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            Thread.sleep(forTimeInterval: 2) // Let the rotation and screenshot orientation settle.
            XCTAssertTrue(audio.waitForExistence(timeout: 5))
            XCTAssertTrue(favourite.isHittable)
            let wide = XCTAttachment(screenshot: app.screenshot())
            wide.name = "Populated landscape player"; wide.lifetime = .keepAlways; add(wide)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testHiddenStreamDiagnosticsCanBeUnlocked() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let version = app.staticTexts["Version"]
        for _ in 0..<5 {
            if version.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(version.isHittable)
        for _ in 0..<5 { version.tap() }
        let diagnostics = app.buttons["streamDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Stream Diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["Record Stream Diagnostics"].exists)
        XCTAssertTrue(app.staticTexts["Metadata summary"].exists)
        let focus = app.segmentedControls["diagnosticFocus"]
        XCTAssertTrue(focus.exists)
        focus.buttons["All"].tap()
        XCTAssertTrue(focus.buttons["All"].isSelected)
        app.buttons["Refresh"].tap()
        XCTAssertTrue(focus.buttons["All"].isSelected)
    }

    @MainActor
    func testSettingsShowsAutoResumeAndAcknowledgements() {
        let app = XCUIApplication()
        app.launch()
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let autoResume = app.switches["autoResume"]
        XCTAssertTrue(autoResume.waitForExistence(timeout: 3))
        XCTAssertEqual(autoResume.value as? String, "0")
        capture("Settings top")
        let sourceLink = app.descendants(matching: .any)["wirelessSourceCode"].firstMatch
        for _ in 0..<5 {
            if sourceLink.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sourceLink.isHittable)
        XCTAssertEqual(sourceLink.label, "View Source on GitHub")
        let licenceLink = app.descendants(matching: .any)["wirelessMITLicence"].firstMatch
        XCTAssertTrue(licenceLink.isHittable)
        XCTAssertEqual(licenceLink.label, "MIT Licence")
        let licenceSummary = app.staticTexts["wirelessLicenceSummary"]
        for _ in 0..<5 {
            if licenceSummary.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(licenceSummary.exists)
        XCTAssertTrue(licenceSummary.label.contains("MIT Licence"))
        XCTAssertTrue(licenceSummary.label.contains("MPL-2.0"))
        let acknowledgements = app.buttons["acknowledgements"]
        XCTAssertTrue(acknowledgements.isHittable)
        capture("Settings about")
        acknowledgements.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["MIT"].waitForExistence(timeout: 3))
        let pocketCasts = app.staticTexts["Pocket Casts for iOS"]
        for _ in 0..<5 {
            if pocketCasts.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(pocketCasts.isHittable)
        XCTAssertTrue(app.staticTexts["MPL-2.0"].exists)
        capture("Acknowledgements")
    }

    @MainActor
    func testSettingsOpensWirelessSupportGuide() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let support = app.buttons["wirelessSupport"]
        XCTAssertTrue(support.waitForExistence(timeout: 3))
        support.tap()
        XCTAssertTrue(app.navigationBars["Support"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Return to Player"].exists)
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
        XCTAssertTrue(app.staticTexts["TV Sync"].exists)
        app.staticTexts["TV Sync"].tap()
        XCTAssertTrue(app.navigationBars["TV Sync"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sync audio to picture")).firstMatch.exists)
    }

    @MainActor
    func testSettingsOpensListeningStats() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let listeningStats = app.buttons["listeningStats"]
        XCTAssertTrue(listeningStats.waitForExistence(timeout: 3))
        listeningStats.tap()

        XCTAssertTrue(app.navigationBars["Listening Stats"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["listeningStatsPage"].exists)
        XCTAssertTrue(app.staticTexts["Time listened"].exists)
        XCTAssertTrue(app.staticTexts["Top Stations"].exists)
        XCTAssertTrue(app.staticTexts["Listening Heatmap"].exists)
        XCTAssertTrue(app.staticTexts["Listening Clock"].exists)

        let tabs = ["week", "month", "year", "lifetime"].map { app.buttons["statsRange-\($0)"] }
        for tab in tabs { XCTAssertTrue(tab.isHittable) }
        let left = tabs.first!.frame.minX
        let right = tabs.last!.frame.maxX
        XCTAssertEqual((left + right) / 2, app.frame.midX, accuracy: 2, "Period tabs should be centred")
        for tab in tabs {
            XCTAssertEqual(tab.frame.midY, tabs[0].frame.midY, accuracy: 1)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }
        tabs[0].tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Listening Stats"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStatsPeriodSelectionMatchesAutohop() {
        let app = XCUIApplication()
        app.launchEnvironment["WIRELESS_STATS_PREVIEW"] = "1"
        app.launch()
        let tabs = ["week", "month", "year", "lifetime"].map { app.buttons["statsRange-\($0)"] }
        XCTAssertTrue(tabs[0].waitForExistence(timeout: 10))
        func assertCentred() {
            for tab in tabs { XCTAssertTrue(tab.isHittable) }
            XCTAssertEqual((tabs[0].frame.minX + tabs[3].frame.maxX) / 2, app.frame.midX, accuracy: 2)
            for tab in tabs { XCTAssertEqual(tab.frame.midY, tabs[0].frame.midY, accuracy: 1) }
        }
        assertCentred()
        XCTAssertTrue(tabs[0].isSelected)
        app.buttons["Last Week"].tap()
        XCTAssertTrue(app.buttons["Last Week"].isSelected)
        tabs[1].tap()
        XCTAssertTrue(app.buttons["Last Month"].isSelected)
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        XCTAssertEqual(tabs[1].label, lastMonth.formatted(.dateTime.month(.wide)))
        tabs[2].tap()
        XCTAssertTrue(app.buttons["Last Year"].isSelected)
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        XCTAssertEqual(tabs[2].label, lastYear.formatted(.dateTime.year()))
        tabs[3].tap()
        XCTAssertFalse(app.buttons["Last Year"].exists)
        tabs[1].tap()
        XCTAssertTrue(app.buttons["Last Month"].isSelected, "Lifetime must preserve the This/Last choice")
        app.buttons["This Month"].tap()
        XCTAssertEqual(tabs[1].label, Date().formatted(.dateTime.month(.wide)))
        let bar = app.buttons["This Month"].frame.union(app.buttons["Last Month"].frame)
        XCTAssertEqual(bar.midX, app.frame.midX, accuracy: 2)
        assertCentred()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Centred glass period tabs and This Last control"
        shot.lifetime = .keepAlways
        add(shot)
        if app.frame.width > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            assertCentred()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testSettingsOpensListeningHistory() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let listeningHistory = app.buttons["listeningHistory"]
        XCTAssertTrue(listeningHistory.waitForExistence(timeout: 3))
        listeningHistory.tap()

        XCTAssertTrue(app.navigationBars["Listening History"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["listeningHistoryPage"].exists)
        XCTAssertTrue(app.staticTexts["LISTENING TIME"].exists)
        XCTAssertTrue(app.staticTexts["SESSIONS"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Listening History"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFavouritesSheetHasFullQueueStyleAndReorderMode() {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favourites, ")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["stationSearch"].exists)
        let reorder = app.buttons["reorderFavourites"]
        XCTAssertTrue(reorder.exists)
        reorder.tap()
        XCTAssertEqual(reorder.label, "Done")
        XCTAssertTrue(app.staticTexts["Drag stations to set their order"].exists)
        reorder.tap()
        XCTAssertEqual(reorder.label, "Reorder")
    }

    @MainActor
    func testAutohopStylePlayerControls() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Playing"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sync"].exists)
        XCTAssertTrue(app.buttons["Sleep Timer"].exists)
        XCTAssertFalse(app.staticTexts["Wireless"].exists)
        XCTAssertFalse(app.staticTexts["Fine Tuning Your Radio Presets"].exists)
        XCTAssertTrue(app.staticTexts["playbackStatus"].exists)
        let favourites = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favourites, ")).firstMatch
        XCTAssertTrue(favourites.exists)
        XCTAssertTrue(favourites.label.hasSuffix(" stations"))
        XCTAssertTrue(app.descendants(matching: .any)["audioSourceSelector"].exists)
        XCTAssertEqual(app.buttons["Audio Controls"].frame.width, 44, accuracy: 1)
        XCTAssertEqual(app.buttons["Sleep Timer"].frame.width, 44, accuracy: 1)
    }

    @MainActor
    func testTVSyncRevealsOnlyDelayControlsWhenEnabled() {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["BackButton"].waitForExistence(timeout: 3) {
            app.buttons["BackButton"].tap()
        }

        let syncPane = app.buttons["Sync"]
        XCTAssertTrue(syncPane.waitForExistence(timeout: 10))
        syncPane.tap()

        let syncToggle = app.switches["syncEnabled"]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 3))
        if syncToggle.value as? String == "1" { syncToggle.tap() }

        XCTAssertFalse(app.descendants(matching: .any)["syncDelayTile"].exists)
        XCTAssertFalse(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)

        syncToggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["syncDelayTile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Saved audio delay"].exists)
        XCTAssertFalse(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
    }

    @MainActor
    func testAutohopStyleMiniPlayerControlsAndArtwork() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))

        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("3AW")
        let station = app.buttons["Play 3AW Melbourne"]
        XCTAssertTrue(station.waitForExistence(timeout: 30))
        station.tap()

        XCTAssertTrue(app.buttons["Discover"].waitForExistence(timeout: 5))
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.buttons["Return to Player"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].exists || app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Audio Controls"].exists)
        XCTAssertFalse(app.buttons["Sleep Timer"].exists)
        let transport = app.buttons["Pause"].exists ? app.buttons["Pause"] : app.buttons["Play"]
        XCTAssertEqual(transport.frame.width, 44, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Autohop-style Wireless mini-player"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSleepTimerCanBeSetExtendedAndCancelled() {
        let app = XCUIApplication()
        app.launch()
        let sleepTimer = app.buttons["Sleep Timer"]
        XCTAssertTrue(sleepTimer.waitForExistence(timeout: 10))
        sleepTimer.tap()

        let fiveMinutes = app.buttons["Set sleep timer for 5 min"]
        XCTAssertTrue(fiveMinutes.waitForExistence(timeout: 3))
        fiveMinutes.tap()

        XCTAssertTrue(sleepTimer.waitForExistence(timeout: 3))
        sleepTimer.tap()
        XCTAssertTrue(app.staticTexts["sleepTimerCountdown"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["+5 min"].exists)
        app.buttons["+5 min"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Set sleep timer for 5 min"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSyncEnabledProgressLabelsUseMeasuredDelay() {
        let app = XCUIApplication()
        app.launch()
        let returnToPlayer = app.buttons["Return to Player"]
        if returnToPlayer.waitForExistence(timeout: 2) { returnToPlayer.tap() }
        XCTAssertTrue(app.buttons["Sync"].waitForExistence(timeout: 10))
        app.buttons["Sync"].tap()
        let toggle = app.descendants(matching: .any)["syncEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let wasEnabled = toggle.value as? String == "1"
        if !wasEnabled { toggle.tap() }

        app.buttons["Playing"].tap()
        XCTAssertEqual(app.staticTexts["playbackStatus"].label, "TV Sync Enabled")
        XCTAssertEqual(app.staticTexts["playbackStatus"].frame.height, 24, accuracy: 1)
        let measured = app.staticTexts["playbackPositionDetail"].label
        XCTAssertTrue(measured == "Measuring…" || measured.hasPrefix("Measured: "))

        if !wasEnabled {
            app.buttons["Sync"].tap()
            toggle.tap()
        }
    }

    @MainActor
    func testDiscoverRegionTilesAndPriority() {
        let app = XCUIApplication()
        app.launch()
        let discover = app.buttons["Discover"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.tap()
        if !app.buttons["browseNetworks"].waitForExistence(timeout: 3) { discover.tap() }
        XCTAssertTrue(app.buttons["browseNetworks"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["browseLocations"].exists)
        XCTAssertTrue(app.buttons["browseGenres"].exists)
        XCTAssertTrue(app.buttons["browseNews"].exists)
        XCTAssertTrue(app.buttons["browseSport"].exists)
        XCTAssertTrue(app.buttons["browseCommunitySpecialist"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Discover regions"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["browseNews"].tap()
        XCTAssertTrue(app.navigationBars["News"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars["News"].buttons.firstMatch.tap()
        app.buttons["browseSport"].tap()
        XCTAssertTrue(app.navigationBars["Sport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars["Sport"].buttons.firstMatch.tap()
        app.buttons["browseLocations"].tap()
        XCTAssertTrue(app.navigationBars["Locations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["browseNational"].exists)
        XCTAssertTrue(app.buttons["region-Melbourne"].exists)
        app.buttons["region-Melbourne"].tap()
        XCTAssertTrue(app.navigationBars["Melbourne"].waitForExistence(timeout: 5))
        let playRows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play "))
        XCTAssertGreaterThan(playRows.count, 0)
        XCTAssertTrue(app.buttons["Return to Player"].exists)
        let regionShot = XCTAttachment(screenshot: app.screenshot())
        regionShot.name = "Melbourne priority"; regionShot.lifetime = .keepAlways; add(regionShot)
        playRows.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Sync"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        app.buttons["Discover"].tap()
        app.buttons["browseLocations"].tap()
        app.buttons["browseNational"].tap()
        XCTAssertTrue(app.navigationBars["National"].waitForExistence(timeout: 5))
        app.buttons["Return to Player"].tap()
        app.buttons["Discover"].tap()
        app.buttons["browseLocations"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["browseOtherLocations"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["state-Victoria"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["state-Victoria"].exists)
        app.buttons["state-Victoria"].tap()
        XCTAssertTrue(app.navigationBars["Victoria"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).count, 0)
    }

    @MainActor
    func testDiscoverGenresBrowseAndScopedSearch() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["browseGenres"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Find your station"].exists)
        XCTAssertTrue(app.staticTexts["News and Talkback"].exists)
        XCTAssertTrue(app.buttons["browseNews"].exists)
        XCTAssertTrue(app.buttons["browseSport"].exists)
        XCTAssertTrue(app.buttons["browseCommunitySpecialist"].exists)
        app.buttons["browseGenres"].tap()
        XCTAssertTrue(app.navigationBars["Music"].waitForExistence(timeout: 5))
        let search = app.textFields["genreSearch"]
        XCTAssertTrue(search.exists)
        XCTAssertTrue(app.buttons["browse-genre-Country"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["browse-genre-News"].exists)
        XCTAssertFalse(app.buttons["browse-genre-Sport"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Discover Genres"; shot.lifetime = .keepAlways; add(shot)
        search.tap(); search.typeText("Country")
        XCTAssertTrue(app.buttons["browse-genre-Country"].exists)
        XCTAssertFalse(app.buttons["browse-genre-Rock"].exists)
        app.buttons["browse-genre-Country"].tap()
        XCTAssertTrue(app.navigationBars["Country"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play Nova Fresh Country"].waitForExistence(timeout: 10))
        for _ in 0..<5 where !app.buttons["Play Triple M Country"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["Play Triple M Country"].exists)
        XCTAssertFalse(app.buttons["Play KIIS Dance"].exists)
        let stations = XCTAttachment(screenshot: app.screenshot()); stations.name = "Country stations"; stations.lifetime = .keepAlways; add(stations)
        let stationSearch = app.textFields["stationSearch"]
        for _ in 0..<5 where !stationSearch.isHittable { app.swipeDown() }
        stationSearch.tap(); stationSearch.typeText("Nova")
        XCTAssertTrue(app.buttons["Play Nova Fresh Country"].exists)
        XCTAssertFalse(app.buttons["Play Triple M Country"].exists)
        app.navigationBars["Country"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Music"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSydneyShowsTopRatingStationsInPopularityOrder() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["browseLocations"].waitForExistence(timeout: 10))
        app.buttons["browseLocations"].tap()
        XCTAssertTrue(app.buttons["region-Sydney"].waitForExistence(timeout: 5))
        app.buttons["region-Sydney"].tap()

        XCTAssertTrue(app.navigationBars["Sydney"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Top Rating Stations"].waitForExistence(timeout: 30))
        let smooth = app.buttons["Play Smooth FM 95.3"]
        let twoGB = app.buttons["Play 2GB"]
        let nova = app.buttons["Play Nova 96.9"]
        XCTAssertTrue(smooth.exists)
        XCTAssertTrue(twoGB.exists)
        XCTAssertTrue(nova.exists)
        XCTAssertLessThan(smooth.frame.minY, twoGB.frame.minY)
        XCTAssertLessThan(twoGB.frame.minY, nova.frame.minY)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Sydney top rating stations"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testMelbourneShowsTopRatingStationsInPopularityOrder() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["browseLocations"].waitForExistence(timeout: 10))
        app.buttons["browseLocations"].tap()
        XCTAssertTrue(app.buttons["region-Melbourne"].waitForExistence(timeout: 5))
        app.buttons["region-Melbourne"].tap()

        XCTAssertTrue(app.navigationBars["Melbourne"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Top Rating Stations"].waitForExistence(timeout: 30))
        let threeAW = app.buttons["Play 3AW Melbourne"]
        let gold = app.buttons["Play GOLD104.3"]
        let smooth = app.buttons["Play Smooth FM 91.5"]
        XCTAssertTrue(threeAW.exists)
        XCTAssertTrue(gold.exists)
        XCTAssertTrue(smooth.exists)
        XCTAssertLessThan(threeAW.frame.minY, gold.frame.minY)
        XCTAssertLessThan(gold.frame.minY, smooth.frame.minY)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Melbourne top rating stations"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testBrisbaneShowsTopRatingStationsInPopularityOrder() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["browseLocations"].waitForExistence(timeout: 10))
        app.buttons["browseLocations"].tap()
        XCTAssertTrue(app.buttons["region-Brisbane"].waitForExistence(timeout: 5))
        app.buttons["region-Brisbane"].tap()

        XCTAssertTrue(app.navigationBars["Brisbane"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Top Rating Stations"].waitForExistence(timeout: 30))
        let tripleM = app.buttons["Play Triple M Brisbane 104.5"]
        let fourBH = app.buttons["Play 4BH"]
        let b105 = app.buttons["Play B105 Brisbane"]
        XCTAssertTrue(tripleM.exists)
        XCTAssertTrue(fourBH.exists)
        XCTAssertTrue(b105.exists)
        XCTAssertLessThan(tripleM.frame.minY, fourBH.frame.minY)
        XCTAssertLessThan(fourBH.frame.minY, b105.frame.minY)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Brisbane top rating stations"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testDiscoverNetworkBrowserUsesFullPageNavigation() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        let networks = app.buttons["browseNetworks"]
        XCTAssertTrue(networks.waitForExistence(timeout: 10))
        networks.tap()
        XCTAssertTrue(app.navigationBars["Networks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Major broadcasters"].exists)
        XCTAssertTrue(app.staticTexts["ABC"].exists)
        XCTAssertTrue(app.staticTexts["ACE Radio"].exists)
        XCTAssertTrue(app.staticTexts["ARN Regional"].exists)
        XCTAssertTrue(app.staticTexts["All Networks"].exists)
        let networksScreenshot = XCTAttachment(screenshot: app.screenshot())
        networksScreenshot.name = "Networks major broadcasters"
        networksScreenshot.lifetime = .keepAlways
        add(networksScreenshot)
        XCTAssertFalse(app.textFields["locationSearch"].exists)
        XCTAssertFalse(app.searchFields["Search networks"].exists)
        let abc = app.buttons["browse-network-ABC"]
        XCTAssertTrue(abc.waitForExistence(timeout: 30))
        abc.tap()
        XCTAssertTrue(app.navigationBars["ABC"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["abc-subnetwork-ABC Local Radio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["abc-subnetwork-Radio National"].exists)
        XCTAssertTrue(app.buttons["abc-subnetwork-ABC Sport"].exists)
        XCTAssertTrue(app.buttons["abc-subnetwork-ABC Country"].exists)
        app.buttons["abc-subnetwork-Triple J"].tap()
        XCTAssertTrue(app.navigationBars["Triple J"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["triple-j-group-national"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["triple-j-group-specialty"].exists)
        XCTAssertTrue(app.buttons["triple-j-group-stateFeeds"].exists)

        app.buttons["triple-j-group-national"].tap()
        XCTAssertTrue(app.buttons["Play triple j"].waitForExistence(timeout: 10))
        app.navigationBars["triple j"].buttons.firstMatch.tap()

        app.buttons["triple-j-group-specialty"].tap()
        XCTAssertTrue(app.buttons["Play triple j Hottest"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Play triple j Unearthed"].exists)
        app.navigationBars["Specialty Music Stations"].buttons.firstMatch.tap()

        app.buttons["triple-j-group-stateFeeds"].tap()
        XCTAssertTrue(app.buttons["Play ABC triple j (QLD)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Play ABC triple j (WA)"].exists)
        app.navigationBars["State-based triple j feeds"].buttons.firstMatch.tap()
        app.navigationBars["Triple J"].buttons.firstMatch.tap()
        app.buttons["abc-subnetwork-ABC Local Radio"].tap()
        XCTAssertTrue(app.navigationBars["ABC Local Radio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSpecialistNetworkTilesAndOrdering() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["browseNetworks"].waitForExistence(timeout: 10))
        app.buttons["browseNetworks"].tap()

        let specialist = app.buttons["browse-network-Community and Specialist stations"]
        XCTAssertFalse(specialist.exists)
        app.navigationBars["Networks"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["browseCommunitySpecialist"].waitForExistence(timeout: 5))
        app.buttons["browseCommunitySpecialist"].tap()
        for category in ["Community", "Religion", "Foreign Language", "Country Music", "Indigenous", "Arts & Music", "Radio Reading", "Youth & Education", "Seniors", "LGBTQIA+"] {
            XCTAssertTrue(app.buttons["community-and-specialist-stations-subnetwork-\(category)"].exists)
        }

        let lastTile = app.buttons["community-and-specialist-stations-subnetwork-LGBTQIA+"]
        let miniPlayer = app.buttons["Return to Player"]
        XCTAssertTrue(miniPlayer.exists)
        for _ in 0..<8 where miniPlayer.frame.minY - lastTile.frame.maxY < 12 { app.swipeUp() }
        XCTAssertTrue(lastTile.isHittable)
        XCTAssertGreaterThanOrEqual(miniPlayer.frame.minY - lastTile.frame.maxY, 12)
    }

    @MainActor
    func testCommercialNetworkSubnetworkBrowsers() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        app.buttons["browseNetworks"].tap()

        let tripleM = app.buttons["browse-network-Triple M"]
        XCTAssertTrue(tripleM.waitForExistence(timeout: 30))
        tripleM.tap()
        XCTAssertTrue(app.buttons["triple-m-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["triple-m-subnetwork-Regional"].exists)
        XCTAssertTrue(app.buttons["triple-m-subnetwork-Music"].exists)
        XCTAssertTrue(app.buttons["triple-m-subnetwork-Sport"].exists)
        app.navigationBars["Triple M"].buttons.firstMatch.tap()

        let hit = app.buttons["browse-network-Hit Network"]
        XCTAssertTrue(hit.waitForExistence(timeout: 10))
        hit.tap()
        XCTAssertTrue(app.buttons["hit-network-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["hit-network-subnetwork-Regional"].exists)
        XCTAssertTrue(app.buttons["hit-network-subnetwork-Music"].exists)
    }

    @MainActor
    func testARNNetworkSubnetworkBrowsers() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        app.buttons["browseNetworks"].tap()

        let kiis = app.buttons["browse-network-KIIS"]
        XCTAssertTrue(kiis.waitForExistence(timeout: 30))
        kiis.tap()
        XCTAssertTrue(app.buttons["kiis-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["kiis-subnetwork-Music"].exists)
        app.navigationBars["KIIS"].buttons.firstMatch.tap()

        let gold = app.buttons["browse-network-Gold"]
        XCTAssertTrue(gold.waitForExistence(timeout: 10))
        gold.tap()
        XCTAssertTrue(app.buttons["gold-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["gold-subnetwork-Music"].exists)
    }

    @MainActor
    func testNovaEntertainmentNetworkSubnetworkBrowsers() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        app.buttons["browseNetworks"].tap()

        let nova = app.buttons["browse-network-Nova"]
        XCTAssertTrue(nova.waitForExistence(timeout: 30))
        nova.tap()
        XCTAssertTrue(app.buttons["nova-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["nova-subnetwork-Music"].exists)
        app.navigationBars["Nova"].buttons.firstMatch.tap()

        let smooth = app.buttons["browse-network-Smooth"]
        XCTAssertTrue(smooth.waitForExistence(timeout: 10))
        smooth.tap()
        XCTAssertTrue(app.buttons["smooth-subnetwork-Metro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["smooth-subnetwork-Music"].exists)
    }

    @MainActor
    func testSyncOffPreservesSavedDelaySetting() {
        let app = XCUIApplication()
        app.launch()
        let returnToPlayer = app.buttons["Return to Player"]
        if returnToPlayer.waitForExistence(timeout: 2) { returnToPlayer.tap() }
        XCTAssertTrue(app.buttons["Sync"].waitForExistence(timeout: 10))
        app.buttons["Sync"].tap()
        let toggle = app.descendants(matching: .any)["syncEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.value as? String != "1" { toggle.tap() }
        let slider = app.sliders["Audio delay"]
        slider.adjust(toNormalizedSliderPosition: 0.65)
        let savedDelay = slider.value as? String
        toggle.tap()
        XCTAssertFalse(slider.isEnabled)
        XCTAssertFalse(app.buttons["Increase delay by half a second"].isEnabled)
        XCTAssertEqual(slider.value as? String, savedDelay)
        app.terminate(); app.launch()
        app.buttons["Sync"].tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(slider.isEnabled)
        XCTAssertEqual(slider.value as? String, savedDelay)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Sync disabled"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Playing"].tap()
        app.buttons["Play"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 20)
        app.buttons["Audio Controls"].tap()
        app.buttons["MP3"].tap()
        app.buttons["Close"].tap()
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 20)
        app.buttons["Pause"].tap()
        app.buttons["Sync"].tap()
        toggle.tap()
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.value as? String, savedDelay)
        app.buttons["Playing"].tap()
        XCTAssertTrue(app.buttons["Play"].exists) // Changing mode must not undo Pause.
        app.buttons["Sync"].tap()
        slider.adjust(toNormalizedSliderPosition: 0)
    }

    @MainActor
    func testPanesDelayAndFavouritesPersist() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.sliders["Audio delay"].exists)
        app.buttons["Sync"].tap()
        let slider = app.sliders["Audio delay"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.4)
        let selected = slider.value as? String
        Thread.sleep(forTimeInterval: 0.5)
        let syncShot = XCTAttachment(screenshot: app.screenshot())
        syncShot.name = "Sync pane"
        syncShot.lifetime = .keepAlways
        add(syncShot)
        app.buttons["Playing"].tap()
        XCTAssertFalse(slider.exists)
        app.swipeLeft()
        XCTAssertTrue(slider.isHittable)
        XCTAssertEqual(slider.value as? String, selected)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(slider.exists)
        app.buttons["Sync"].tap()
        XCTAssertEqual(slider.value as? String, selected)
        app.buttons["Playing"].tap()
        app.buttons["Discover"].tap()
        app.textFields["stationSearch"].tap()
        app.textFields["stationSearch"].typeText("SEN 1116")
        let remove = app.buttons["Remove SEN 1116 from Favourites"]
        if !remove.exists { app.buttons["Add SEN 1116 to Favourites"].tap() }
        remove.tap()
        XCTAssertTrue(app.buttons["Remove from Favourites"].waitForExistence(timeout: 3))
        app.buttons["Remove from Favourites"].tap()
        app.buttons["Return to Player"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favourites, ")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No favourites yet"].waitForExistence(timeout: 3))
        app.buttons["Browse Stations"].tap()
        app.textFields["stationSearch"].tap()
        app.textFields["stationSearch"].typeText("SEN 1116")
        XCTAssertTrue(app.buttons["Add SEN 1116 to Favourites"].waitForExistence(timeout: 3))
        app.buttons["Add SEN 1116 to Favourites"].tap()
        app.buttons["Return to Player"].tap()
        app.buttons["Sync"].tap()
        slider.adjust(toNormalizedSliderPosition: 0)
        app.buttons["Playing"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let playingShot = XCTAttachment(screenshot: app.screenshot())
        playingShot.name = "Playing pane"
        playingShot.lifetime = .keepAlways
        add(playingShot)
    }

    @MainActor
    func testDiscoverDirectoryPlaybackAndFavouritePersistence() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 2) {
            app.buttons["Discover"].tap()
        } else {
            XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))
        }
        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("3AW")
        let play = app.buttons["Play 3AW Melbourne"]
        XCTAssertTrue(play.waitForExistence(timeout: 45))
        let favourite = app.buttons["Add 3AW Melbourne to Favourites"]
        if favourite.exists { favourite.tap() }
        play.tap()
        XCTAssertTrue(app.staticTexts["3AW Melbourne"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Details"].exists)
        app.buttons["Details"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailsStationArtwork"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stationDescriptionCard"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stationMetadataGrid"].exists)
        XCTAssertTrue(app.staticTexts["LOCATION"].exists)
        XCTAssertTrue(app.staticTexts["STATE"].exists)
        XCTAssertTrue(app.staticTexts["FREQUENCY"].exists)
        XCTAssertTrue(app.staticTexts["REGION"].exists)
        XCTAssertTrue(app.staticTexts["NETWORK"].exists)
        XCTAssertFalse(app.staticTexts["STATION LOCATION"].exists)
        XCTAssertFalse(app.staticTexts["STATION STATE"].exists)
        XCTAssertTrue(app.links["stationContact-Talkback-0"].exists)
        app.buttons["Playing"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 50)
        XCTAssertFalse(app.staticTexts["On SEN 1116"].exists)
        app.buttons["Pause"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Playing"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3AW Melbourne"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favourites, ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Play 3AW Melbourne"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Directory favourites"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Remove 3AW Melbourne from Favourites"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove from Favourites"].waitForExistence(timeout: 3))
        app.buttons["Remove from Favourites"].tap()
    }

    @MainActor
    func testDirectoryHLSPlaybackAndReturnToSEN() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Sync"].tap()
        let syncToggle = app.descendants(matching: .any)["syncEnabled"]
        if syncToggle.value as? String != "0" { syncToggle.tap() }
        app.buttons["Playing"].tap()
        app.buttons["Discover"].tap()
        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("102.5 ABC Perth")
        let abc = app.buttons["Play 102.5 ABC Perth"]
        XCTAssertTrue(abc.waitForExistence(timeout: 45)); abc.tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 45)
        XCTAssertFalse(app.staticTexts["On SEN 1116"].exists)
        app.buttons["Discover"].tap()
        search.tap(); search.typeText("SEN 1116")
        let sen = app.buttons["Play SEN 1116"]
        XCTAssertTrue(sen.waitForExistence(timeout: 10)); sen.tap()
        app.buttons["Sync"].tap()
        syncToggle.tap()
        XCTAssertTrue(app.sliders["Audio delay"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["Audio delay"].isEnabled)
        app.buttons["Playing"].tap()
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 45)
        XCTAssertTrue(app.staticTexts["SEN 1116"].exists)
        app.buttons["Pause"].tap()
        app.buttons["Sync"].tap()
        syncToggle.tap()
    }

    @MainActor
    func testLivePlaybackAndPause() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 35)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        app.buttons["Audio Controls"].tap()
        app.buttons["MP3"].tap()
        app.buttons["Close"].tap()
        app.buttons["Play"].tap()
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 35)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPreparedStationWaitsForPlayAndPauseStaysPaused() {
        let app = XCUIApplication()
        app.launchArguments = ["-syncEnabled", "NO", "-syncEnabledDefaultOffMigration.v1", "YES",
                               "-vocalBoostLevel", "off", "-autoResumePlayback", "NO",
                               "-streamDiagnosticLoggingEnabled", "YES"]
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 2) {
            app.buttons["Discover"].tap()
        }
        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("3AW")
        let station = app.buttons["Play 3AW Melbourne"]
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        station.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        app.terminate()
        app.launch()
        // The restored station prepares silently, without changing playback intent.
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
        app.buttons["Play"].tap()
        let playing = NSPredicate(format: "label == %@", "Playing")
        expectation(for: playing, evaluatedWith: app.staticTexts["playbackStatus"])
        waitForExpectations(timeout: 40)
        app.buttons["Pause"].tap()
        // Longer than the stall watchdog: deliberate Pause must not reconnect.
        Thread.sleep(forTimeInterval: 16)
        XCTAssertTrue(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
    }

    @MainActor
    func testSelectedStreamPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launch()
        let returnToPlayer = app.buttons["Return to Player"]
        if returnToPlayer.waitForExistence(timeout: 2) { returnToPlayer.tap() }
        app.buttons["Discover"].tap()
        let search = app.textFields["stationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("SEN 1116")
        let sen = app.buttons["Play SEN 1116"]
        XCTAssertTrue(sen.waitForExistence(timeout: 30)); sen.tap()
        if app.buttons["Pause"].waitForExistence(timeout: 3) { app.buttons["Pause"].tap() }
        app.buttons["Audio Controls"].tap()
        reveal(app.buttons["streamPicker"], in: app)
        app.buttons["streamPicker"].tap()
        let mp3 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "MP3")).firstMatch
        XCTAssertTrue(mp3.waitForExistence(timeout: 3)); mp3.tap()
        app.buttons["Close"].tap()

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Audio Controls"].waitForExistence(timeout: 10))
        app.buttons["Audio Controls"].tap()
        let picker = app.descendants(matching: .any)["streamPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        let restoredSelection = "\(picker.label) \(String(describing: picker.value))"
        XCTAssertTrue(restoredSelection.contains("MP3"), "Restored picker: \(picker.debugDescription)")
    }
}
