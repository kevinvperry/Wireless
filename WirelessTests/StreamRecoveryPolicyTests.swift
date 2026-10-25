import XCTest

final class StreamRecoveryPolicyTests: XCTestCase {
    func testExhaustingAlternatesStartsAnotherCycle() {
        var policy = StreamRecoveryPolicy()
        let alternate = policy.nextAttempt(streamCount: 2, currentIndex: 0)
        XCTAssertEqual(alternate.index, 1)
        XCTAssertEqual(alternate.wait, 1)
        let restart = policy.nextAttempt(streamCount: 2, currentIndex: 1)
        XCTAssertEqual(restart.index, 0)
        XCTAssertEqual(restart.cycle, 2)
        XCTAssertEqual(policy.nextAttempt(streamCount: 2, currentIndex: 0).index, 1)
    }

    func testSingleStreamKeepsRetryingWithCappedBackoff() {
        var policy = StreamRecoveryPolicy()
        let waits = (0..<9).map { _ in policy.nextAttempt(streamCount: 1, currentIndex: 0).wait }
        XCTAssertEqual(waits, [1, 2, 4, 8, 15, 15, 15, 15, 15])
    }

    func testBriefRecoveryDoesNotResetBackoff() {
        var policy = StreamRecoveryPolicy()
        _ = policy.nextAttempt(streamCount: 1, currentIndex: 0)
        let start = Date(timeIntervalSince1970: 100)
        policy.recordPlayback(at: start)
        policy.recordPlayback(at: start.addingTimeInterval(3))
        XCTAssertEqual(policy.nextAttempt(streamCount: 1, currentIndex: 0).wait, 2)
        // A fresh burst must earn a new continuous healthy interval.
        policy.recordPlayback(at: start.addingTimeInterval(20))
        XCTAssertEqual(policy.nextAttempt(streamCount: 1, currentIndex: 0).wait, 4)
    }

    func testSustainedRecoveryAndManualRestartResetBackoff() {
        var policy = StreamRecoveryPolicy()
        for _ in 0..<5 { _ = policy.nextAttempt(streamCount: 1, currentIndex: 0) }
        let start = Date(timeIntervalSince1970: 100)
        policy.recordPlayback(at: start)
        policy.recordPlayback(at: start.addingTimeInterval(15))
        XCTAssertEqual(policy.nextAttempt(streamCount: 1, currentIndex: 0).wait, 1)
        policy.reset()
        XCTAssertEqual(policy.nextAttempt(streamCount: 1, currentIndex: 0).cycle, 2)
    }
}
