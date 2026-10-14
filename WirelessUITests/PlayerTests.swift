import XCTest

final class PlayerTests: XCTestCase {
    @MainActor
    func testHiddenStreamDiagnosticsCanBeUnlocked() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Discover"].waitForExistence(timeout: 3) { app.buttons["Discover"].tap() }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let version = app.staticTexts["Version"]
        XCTAssertTrue(version.waitForExistence(timeout: 3))
        for _ in 0..<5 { version.tap() }
        let diagnostics = app.staticTexts["Stream Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Stream Diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["Record Stream Diagnostics"].exists)
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
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
        XCTAssertTrue(app.staticTexts["TV Sync"].exists)
        app.staticTexts["TV Sync"].tap()
        XCTAssertTrue(app.navigationBars["TV Sync"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sync audio to picture")).firstMatch.exists)
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
        XCTAssertEqual(app.staticTexts["playbackStatus"].label, "Sync Enabled")
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
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.buttons["browseNational"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["region-Melbourne"].exists)
        XCTAssertTrue(app.buttons["browseNetworks"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Discover regions"; screenshot.lifetime = .keepAlways; add(screenshot)
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
        app.buttons["browseNational"].tap()
        XCTAssertTrue(app.navigationBars["National"].waitForExistence(timeout: 5))
        app.buttons["Return to Player"].tap()
        app.buttons["Discover"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["browseLocations"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["state-Victoria"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["state-Victoria"].exists)
        app.buttons["state-Victoria"].tap()
        XCTAssertTrue(app.navigationBars["Victoria"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).count, 0)
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
        let abc = app.buttons["browse-network-ABC"]
        XCTAssertTrue(abc.waitForExistence(timeout: 30))
        abc.tap()
        XCTAssertTrue(app.navigationBars["ABC"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch.waitForExistence(timeout: 10))
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
