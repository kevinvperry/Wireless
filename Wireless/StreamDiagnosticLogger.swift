import Foundation

/// A stream-focused adaptation of Autohop's capped, exportable diagnostic log.
/// Entries intentionally omit stream URLs, audio-route names and track metadata.
final class StreamDiagnosticLogger: @unchecked Sendable {
    static let shared = StreamDiagnosticLogger()

    private let queue = DispatchQueue(label: "au.com.kevmarl.Wireless.stream-diagnostics")
    private let defaults = UserDefaults.standard
    private let enabledKey = "streamDiagnosticLoggingEnabled"
    private let maximumBytes = 2 * 1_024 * 1_024
    private let fileManager = FileManager.default
    private let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set {
            defaults.set(newValue, forKey: enabledKey)
            if newValue {
                record("diagnostics.enabled", "Stream diagnostics enabled", force: true)
            }
        }
    }

    private init() {}

    func record(
        _ event: String,
        _ message: String,
        metadata: [String: String] = [:],
        force: Bool = false
    ) {
        guard force || isEnabled else { return }
        let safeEvent = Self.clean(event)
        let safeMessage = Self.clean(message)
        let fields = metadata
            .map { (Self.clean($0.key), Self.clean($0.value)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\(Self.quote($0.1))" }
            .joined(separator: " ")
        queue.async { [self] in
            let timestamp = formatter.string(from: Date())
            let line = "\(timestamp) \(safeEvent) \(Self.quote(safeMessage))" + (fields.isEmpty ? "" : " \(fields)") + "\n"
            append(line)
        }
    }

    func recentLines(limit: Int = 500) -> [String] {
        queue.sync {
            guard let data = try? Data(contentsOf: logURL),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return Array(text.split(whereSeparator: \.isNewline).suffix(max(1, limit))).map(String.init)
        }
    }

    func writeRedactedExport(to destination: URL) throws {
        try queue.sync {
            var output = "Wireless Stream Diagnostic Log\n"
            output += "Version: \(Self.appVersion)\n"
            output += "Created: \(formatter.string(from: Date()))\n"
            output += "Privacy: stream URLs are recorded; authentication values, device names and programme metadata are excluded.\n\n"
            if let previous = try? String(contentsOf: rotatedURL, encoding: .utf8) { output += previous }
            if let current = try? String(contentsOf: logURL, encoding: .utf8) { output += current }
            try Self.redact(output).write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    func clear() {
        queue.sync {
            try? fileManager.removeItem(at: logURL)
            try? fileManager.removeItem(at: rotatedURL)
        }
    }

    private func append(_ line: String) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if (try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 + line.utf8.count > maximumBytes }) == true {
                try? fileManager.removeItem(at: rotatedURL)
                try fileManager.moveItem(at: logURL, to: rotatedURL)
            }
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging must never interfere with playback.
        }
    }

    private var directoryURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("Wireless", isDirectory: true)
    }
    private var logURL: URL { directoryURL.appendingPathComponent("stream-diagnostics.log") }
    private var rotatedURL: URL { directoryURL.appendingPathComponent("stream-diagnostics.previous.log") }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private static func clean(_ value: String) -> String {
        redact(value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func redact(_ value: String) -> String {
        var result = value
        let patterns = [#"(?i)(token|key|signature|sig|auth)=([^\s&\"]+)"#]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return result
    }
}
