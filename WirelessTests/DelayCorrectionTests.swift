import XCTest

final class DelayCorrectionTests: XCTestCase {
    func testBriefPacketArrivalJitterDoesNotMovePlayback() {
        var controller = DelayCorrectionController()
        for step in 0..<100 {
            let observed = step.isMultiple(of: 5) ? 15.35 : 15.0
            XCTAssertFalse(controller.observe(measured: observed, target: 15, now: Double(step) / 10))
        }
    }

    func testSustainedLagJumpsForward() {
        var controller = DelayCorrectionController()
        for step in 0..<20 {
            XCTAssertFalse(controller.observe(measured: 16, target: 15, now: Double(step) / 10))
        }
        XCTAssertTrue(controller.observe(measured: 16, target: 15, now: 2))
    }

    func testSourceRunningBehindDoesNotAddSilence() {
        var controller = DelayCorrectionController()
        for step in 0..<100 {
            XCTAssertFalse(controller.observe(measured: 14, target: 15, now: Double(step) / 10))
        }
    }

    func testReturningToTargetCancelsPendingCorrection() {
        var controller = DelayCorrectionController()
        XCTAssertFalse(controller.observe(measured: 16, target: 15, now: 0))
        XCTAssertFalse(controller.observe(measured: 15, target: 15, now: 1))
        for step in 11..<30 {
            XCTAssertFalse(controller.observe(measured: 15, target: 15, now: Double(step) / 10))
        }
    }
}
