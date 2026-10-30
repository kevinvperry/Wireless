import XCTest
import AVFoundation
import ShazamKit

private final class StreamingCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(SHSession, AVAudioFramePosition)] = []
    func append(_ session: SHSession, _ time: AVAudioTime) {
        lock.lock(); defer { lock.unlock() }; calls.append((session, time.sampleTime))
    }
    var snapshot: [(SHSession, AVAudioFramePosition)] {
        lock.lock(); defer { lock.unlock() }; return calls
    }
}
final class StreamingSongRecognitionTests: XCTestCase {
    private func pcm(frames: UInt32 = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        pcm.frameLength = frames
        memset(pcm.floatChannelData![0], 0, Int(frames) * MemoryLayout<Float>.size)
        return pcm
    }
    func testFeedsFirstBufferImmediatelyAndUsesContiguousTimes() async {
        let calls = StreamingCalls()
        let submitted = expectation(description: "two immediate buffers")
        submitted.expectedFulfillmentCount = 2
        let worker = SongRecognitionWorker(submitBuffer: { session, _, time in
            calls.append(session, time); submitted.fulfill()
        }) { _ in XCTFail("Short mocked stream must not finish") }
        worker.append(pcm()); worker.append(pcm())
        await fulfillment(of: [submitted], timeout: 2)
        let result = calls.snapshot
        XCTAssertEqual(result.map(\.1), [0, 1024])
        XCTAssertTrue(result[0].0 === result[1].0)
        worker.cancel()
    }
    func testEarlyNoMatchContinuesAndDeadlineReturnsNoMatch() async {
        let calls = StreamingCalls()
        let submitted = expectation(description: "first buffer")
        let continued = expectation(description: "additional audio after no-match")
        let finished = expectation(description: "no-match only at deadline")
        let worker = SongRecognitionWorker(submitBuffer: { session, _, time in
            calls.append(session, time)
            if time.sampleTime == 0 { submitted.fulfill() } else { continued.fulfill() }
        }) { event in
            guard case .noMatch = event else { return XCTFail("Unexpected result") }; finished.fulfill()
        }
        worker.append(pcm())
        await fulfillment(of: [submitted], timeout: 2)
        worker.session(calls.snapshot[0].0, didNotFindMatchFor: SHSignatureGenerator().signature(), error: nil)
        worker.append(pcm())
        await fulfillment(of: [continued], timeout: 2)
        worker.deadlineReached()
        await fulfillment(of: [finished], timeout: 2)
        worker.cancel()
    }
    func testFallbackCreatesNewSessionAndRejectsOldCallback() async {
        let calls = StreamingCalls()
        let submitted = expectation(description: "first source")
        let restarted = expectation(description: "fallback source")
        let ignored = expectation(description: "old callback ignored")
        let context = ShazamDiagnosticContext(sink: { event, _, _ in
            if event == "recognition.callback.ignored" { ignored.fulfill() }
        })
        let worker = SongRecognitionWorker(diagnostics: context, submitBuffer: { session, _, time in
            calls.append(session, time)
            if calls.snapshot.count == 1 { submitted.fulfill() } else { restarted.fulfill() }
        }) { _ in XCTFail("Old callback must not end fallback capture") }
        worker.append(pcm())
        await fulfillment(of: [submitted], timeout: 2)
        let old = calls.snapshot[0].0
        worker.resetCaptureForFallback(); worker.append(pcm())
        await fulfillment(of: [restarted], timeout: 2)
        XCTAssertFalse(old === calls.snapshot[1].0)
        XCTAssertEqual(calls.snapshot[1].1, 0)
        worker.session(old, didNotFindMatchFor: SHSignatureGenerator().signature(), error: NSError(domain: "stale", code: 1))
        await fulfillment(of: [ignored], timeout: 2)
        worker.cancel()
    }
    @MainActor func testMatchingKeepsCaptureRunningUntilDeadline() async throws {
        let matching = expectation(description: "minimum duration reached")
        let trace: ShazamDiagnosticContext.Sink = { event, _, _ in
            if event == "recognition.attempt.matching" { matching.fulfill() }
        }
        let recognition = SongRecognition(timeout: .seconds(5), diagnosticSink: trace, submitBuffer: { _, _, _ in })
        var stops = 0
        recognition.stopAudio = { stops += 1 }
        let worker = recognition.start(explanation: "test")
        let initial = stops
        worker.append(pcm(frames: 160_000))
        await fulfillment(of: [matching], timeout: 2)
        XCTAssertEqual(recognition.state, .matching)
        XCTAssertEqual(stops, initial, "Matching must continue receiving audio")
        recognition.cancel()
        XCTAssertEqual(stops, initial + 1)
    }
}
