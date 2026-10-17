import XCTest

@MainActor
final class SleepScheduleServiceTests: XCTestCase {
    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testWindowSpanningMidnightAndAllDayWindow() {
        let service = SleepScheduleService()
        service.updateConfig(.init(enabled: true, startMinutes: 21 * 60, endMinutes: 6 * 60, durationMinutes: 20), isPlaying: false)
        XCTAssertTrue(service.isWithinWindow(date(hour: 23)))
        XCTAssertTrue(service.isWithinWindow(date(hour: 5, minute: 59)))
        XCTAssertFalse(service.isWithinWindow(date(hour: 6)))
        XCTAssertFalse(service.isWithinWindow(date(hour: 12)))

        service.updateConfig(.init(enabled: true, startMinutes: 600, endMinutes: 600, durationMinutes: 20), isPlaying: false)
        XCTAssertTrue(service.isWithinWindow(date(hour: 3)))
    }

    func testCountdownPromptsAndResponseStartsNextCycle() {
        let service = SleepScheduleService()
        // An all-day window keeps the test independent of the time it runs.
        service.updateConfig(.init(enabled: true, startMinutes: 0, endMinutes: 0, durationMinutes: 10), isPlaying: false)
        var prompts = 0
        service.onPrompt = { prompts += 1 }
        service.playbackStarted()
        XCTAssertEqual(service.minutesUntilPrompt, 10)

        for _ in 0..<(10 * 60 * 2) { service.tick(isPlaying: true) }
        XCTAssertTrue(service.isPrompting)
        XCTAssertEqual(prompts, 1)

        service.userResponded()
        XCTAssertFalse(service.isPrompting)
        XCTAssertEqual(service.minutesUntilPrompt, 10)
        service.reset()
    }

    func testCountdownOnlyAdvancesWhilePlayingAndManualTimerSuspends() {
        let service = SleepScheduleService()
        service.updateConfig(.init(enabled: true, startMinutes: 0, endMinutes: 0, durationMinutes: 10), isPlaying: false)
        service.playbackStarted()
        for _ in 0..<100 { service.tick(isPlaying: false) }
        XCTAssertEqual(service.phase, .counting(remaining: 600))

        service.suspendForSession()
        XCTAssertEqual(service.phase, .idle)
        service.tick(isPlaying: true)
        XCTAssertEqual(service.phase, .idle)

        // A new listening session clears the suspension.
        service.playbackStarted()
        XCTAssertEqual(service.minutesUntilPrompt, 10)
    }

    func testDisablingResetsAndSettingsKeepSavedValues() {
        let defaults = UserDefaults(suiteName: "SleepScheduleServiceTests")!
        defaults.removePersistentDomain(forName: "SleepScheduleServiceTests")
        let settings = SleepScheduleSettings(defaults: defaults)
        XCTAssertEqual(settings.config, .init(enabled: false, startMinutes: 1260, endMinutes: 360, durationMinutes: 20))
        settings.enabled = true
        settings.durationMinutes = 40
        settings.enabled = false
        let reloaded = SleepScheduleSettings(defaults: defaults)
        XCTAssertFalse(reloaded.enabled)
        XCTAssertEqual(reloaded.durationMinutes, 40)
    }
}
