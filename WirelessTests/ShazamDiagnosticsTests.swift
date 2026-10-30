import XCTest
import AVFoundation

private final class DiagnosticEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, [String: String])] = []
    func append(_ event: String, _ message: String, _ fields: [String: String]) {
        lock.lock(); defer { lock.unlock() }; entries.append((event, fields))
    }
    var snapshot: [(String, [String: String])] {
        lock.lock(); defer { lock.unlock() }; return entries
    }
}

final class ShazamDiagnosticsTests: XCTestCase {
    func testExportPreservesCorrelatedEventsAndHonoursRecordingSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ShazamDiagnosticsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let logger = StreamDiagnosticLogger(defaults: defaults, directory: directory)
        let context = ShazamDiagnosticContext(sink: { event, message, fields in
            logger.record(event, message, metadata: fields)
        })
        context.record("disabled", "Must not be recorded")
        XCTAssertTrue(logger.recentLines().isEmpty)
        logger.isEnabled = true
        context.record("attempt.started", "Identify", ["source": "https://user:pass@example.com/private?token=secret"])
        context.error("request.failed", "Request failed", NSError(domain: "SHErrorDomain", code: 7))
        logger.isEnabled = false
        context.record("disabled", "Must not be recorded")
        let destination = directory.appendingPathComponent("export.log")
        try logger.writeRedactedExport(to: destination)
        let export = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(export.contains("recognition.attempt.started"))
        XCTAssertTrue(export.contains("recognition.request.failed"))
        XCTAssertTrue(export.contains(context.id.uuidString))
        XCTAssertTrue(export.contains("SHErrorDomain"))
        XCTAssertFalse(export.contains("recognition.disabled"))
        XCTAssertFalse(export.contains("token=secret"))
        XCTAssertFalse(export.contains("user:pass"))
    }

    func testRedactionRemovesCredentialsAndURLSecretsAndIsStable() {
        let input = "https://user:password@example.com/private-path?token=secret#fragment Bearer abc123 {\"access_token\":\"hidden-value\"} eyJabc.def.ghi"
        let safe = ShazamDiagnosticContext.redact(input)
        for secret in ["user:", "password", "private-path", "secret", "fragment", "abc123", "hidden-value", "eyJabc"] {
            XCTAssertFalse(safe.contains(secret), secret)
        }
        XCTAssertTrue(safe.contains("example.com"))
        XCTAssertEqual(ShazamDiagnosticContext.redact(safe), safe)
        XCTAssertFalse(ShazamDiagnosticContext.redact("Cookie: session=private-cookie").contains("private-cookie"))
        XCTAssertFalse(ShazamDiagnosticContext.redact("file:///Users/Someone/private").contains("Someone"))
    }

    func testErrorTreeKeepsActionableDetailsWithoutArbitraryUserInfo() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "Offline https://user:pass@example.com/signed?token=secret",
            NSLocalizedFailureReasonErrorKey: "Network unavailable", "opaquePrivateKey": "never-copy-this"])
        let error = NSError(domain: "SHErrorDomain", code: 201, userInfo: [
            NSLocalizedDescriptionKey: "Request failed", NSUnderlyingErrorKey: underlying,
            NSLocalizedRecoverySuggestionErrorKey: "Retry online"])
        let fields = ShazamDiagnosticContext.errorFields(error)
        XCTAssertEqual(fields["error.code"], "201")
        XCTAssertEqual(fields["error.underlying.code"], "-1009")
        XCTAssertEqual(fields["error.underlying.failureReason"], "Network unavailable")
        XCTAssertEqual(fields["error.recoverySuggestion"], "Retry online")
        XCTAssertFalse(fields.description.contains("never-copy-this"))
        XCTAssertFalse(fields.description.contains("token=secret"))
        var nested = underlying
        for _ in 0..<20 { nested = NSError(domain: "nested", code: 1, userInfo: [NSUnderlyingErrorKey: nested]) }
        XCTAssertTrue(ShazamDiagnosticContext.errorFields(nested).keys.contains { $0.hasSuffix("truncated") })
    }

    func testContextCorrelatesAndRedactsRouteNames() {
        let events = DiagnosticEvents()
        let id = UUID()
        let context = ShazamDiagnosticContext(id: id, fields: ["stationID": "test", "routeTypes": "Speaker"], sink: { events.append($0, $1, $2) },
                                              privateNames: ["Kevin's AirPods", "Speaker"])
        context.record("capture.selected", "Selected capture", ["reason": "Kevin's AirPods disconnected"])
        let event = events.snapshot.first!
        XCTAssertEqual(event.0, "recognition.capture.selected")
        XCTAssertEqual(event.1["attemptID"], id.uuidString)
        XCTAssertEqual(event.1["stationID"], "test")
        XCTAssertEqual(event.1["routeTypes"], "Speaker")
        XCTAssertNotNil(event.1["elapsedSeconds"])
        XCTAssertFalse(event.1.description.contains("Kevin"))
    }

    @MainActor func testTimeoutRecordsSourcePhaseAndSummaryWithSameAttemptID() async throws {
        let events = DiagnosticEvents()
        let recognition = SongRecognition(timeout: .milliseconds(30), diagnosticSink: { events.append($0, $1, $2) })
        _ = recognition.start(explanation: "Test", diagnosticFields: ["captureBackend": "avplayer-hls-output"])
        try await Task.sleep(for: .milliseconds(180))
        let records = events.snapshot
        XCTAssertTrue(records.contains { $0.0 == "recognition.attempt.started" })
        XCTAssertTrue(records.contains { $0.0 == "recognition.attempt.timeout" })
        XCTAssertTrue(records.contains { $0.0 == "recognition.audio.summary" && $0.1["frames"] == "0" })
        XCTAssertEqual(Set(records.compactMap { $0.1["attemptID"] }).count, 1)
        XCTAssertTrue(records.allSatisfy { $0.1["captureBackend"] == "avplayer-hls-output" })
    }

    func testPCMProgressReportsSilenceAndFormatFailure() async {
        let events = DiagnosticEvents()
        let failure = expectation(description: "format failure")
        let summary = expectation(description: "summary")
        let context = ShazamDiagnosticContext(sink: { event, message, fields in
            events.append(event, message, fields)
            if event == "recognition.audio.summary" { summary.fulfill() }
        })
        let worker = SongRecognitionWorker(diagnostics: context) { event in
            if case .failed = event { failure.fulfill() }
        }
        for rate in [44_100.0, 48_000.0] {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
            buffer.frameLength = 1024
            memset(buffer.floatChannelData![0], 0, 4096)
            worker.append(buffer)
        }
        await fulfillment(of: [failure], timeout: 3)
        worker.cancel(reason: "test-finished")
        await fulfillment(of: [summary], timeout: 3)
        let records = events.snapshot
        XCTAssertTrue(records.contains { $0.0 == "recognition.audio.firstBuffer" })
        XCTAssertTrue(records.contains { $0.0 == "recognition.audio.progress" && $0.1["windowRMS"] == "0.0" })
        XCTAssertTrue(records.contains { $0.0 == "recognition.audio.formatChanged" })
        XCTAssertEqual(Set(records.compactMap { $0.1["attemptID"] }), [context.id.uuidString])
    }
}
