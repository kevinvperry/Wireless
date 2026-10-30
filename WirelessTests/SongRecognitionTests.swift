import XCTest
import AVFoundation

final class SongRecognitionTests: XCTestCase {
    @MainActor func testHLSOutputDetachesAndStopIsIdempotent() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native HLS output requires iOS 27") }
        let item = AVPlayerItem(url: URL(string: "http://127.0.0.1/unused.m3u8")!)
        let sample = HLSSongSample(item: item, receive: { _ in XCTFail("No player is running") },
                                   failure: { XCTFail("No player is running") })
        XCTAssertEqual(item.outputs.count, 1)
        sample.stop()
        XCTAssertTrue(item.outputs.isEmpty)
        sample.stop()
        XCTAssertTrue(item.outputs.isEmpty)
    }

    func testCancelledAndReplacedAttemptsRejectLateResults() {
        var attempt = SongRecognitionAttempt()
        let old = attempt.begin()
        XCTAssertTrue(attempt.accepts(old))
        attempt.cancel()
        XCTAssertFalse(attempt.accepts(old))
        let current = attempt.begin()
        XCTAssertFalse(attempt.accepts(old))
        XCTAssertTrue(attempt.accepts(current))
    }

    func testWorkerRejectsFormatChangesRatherThanCombiningDifferentAudio() async {
        let failed = expectation(description: "format discontinuity rejected")
        let worker = SongRecognitionWorker { event in
            if case .failed(let message) = event {
                XCTAssertTrue(message.contains("format changed"))
                failed.fulfill()
            } else { XCTFail("Unexpected recognition event") }
        }
        for rate in [44_100.0, 48_000.0] {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
            pcm.frameLength = 1024
            memset(pcm.floatChannelData![0], 0, 1024 * MemoryLayout<Float>.size)
            worker.append(pcm)
        }
        await fulfillment(of: [failed], timeout: 3)
        worker.cancel()
    }

    @MainActor func testDeadlineStopsSamplingWithoutAnAudioSource() async throws {
        let recognition = SongRecognition(timeout: .milliseconds(40))
        var stops = 0
        recognition.stopAudio = { stops += 1 }
        _ = recognition.start(explanation: "silent source")
        let before = stops
        try await Task.sleep(for: .milliseconds(150))
        guard case .failed(let message) = recognition.state else { return XCTFail("Expected bounded capture failure") }
        XCTAssertTrue(message.contains("enough audio"))
        XCTAssertEqual(stops, before + 1)
    }

    @MainActor func testCancelStopsAudioAndResetsSavingAndRequestState() {
        let recognition = SongRecognition()
        var stops = 0
        recognition.stopAudio = { stops += 1 }
        _ = recognition.start(explanation: "test source")
        XCTAssertEqual(recognition.state, .listening)
        let before = stops
        recognition.cancel()
        XCTAssertEqual(stops, before + 1)
        XCTAssertEqual(recognition.state, .ready)
        XCTAssertFalse(recognition.saving)
        XCTAssertFalse(recognition.saved)
        XCTAssertNil(recognition.saveMessage)
    }

    @MainActor func testUnavailableStopsAttemptAndClearsOldSourceDescription() {
        let recognition = SongRecognition()
        _ = recognition.start(explanation: "old station")
        recognition.unavailable("Turn off TV Sync")
        XCTAssertEqual(recognition.state, .failed("Turn off TV Sync"))
        XCTAssertEqual(recognition.sourceExplanation, "")
        XCTAssertFalse(recognition.state.isWorking)
    }
}
