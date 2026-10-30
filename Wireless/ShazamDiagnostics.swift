import AVFoundation
import Foundation

/// Correlation and bounded, field-aware diagnostics adapted from Autohop's
/// AppLogger. Every layer receives the same context; no audio/signature bytes,
/// credentials, arbitrary NSError userInfo or route/device names are recorded.
struct ShazamDiagnosticContext: Sendable {
    typealias Sink = @Sendable (String, String, [String: String]) -> Void
    let id: UUID
    private let started = ProcessInfo.processInfo.systemUptime
    private let fields: [String: String]
    private let sink: Sink?
    private let privateNames: [String]
    init(id: UUID = UUID(), fields: [String: String] = [:], sink: Sink? = nil, privateNames: [String] = []) {
        self.id = id; self.fields = fields; self.sink = sink; self.privateNames = privateNames.filter { $0.count > 3 }
    }
    var enabled: Bool { sink != nil || StreamDiagnosticLogger.shared.isEnabled }
    func record(_ event: String, _ message: String, _ details: [String: String] = [:]) {
        guard enabled else { return }
        var values = fields.merging(details) { _, new in new }
        values["attemptID"] = id.uuidString
        values["elapsedSeconds"] = String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started)
        values = Dictionary(uniqueKeysWithValues: values.map { key, value in
            var safe = Self.redact(value)
            if key != "routeTypes" && key != "deviceModel" {
                for name in privateNames { safe = safe.replacingOccurrences(of: name, with: "<device-name-redacted>", options: .caseInsensitive) }
            }
            return (key, safe)
        })
        if let sink { sink("recognition." + event, Self.redact(message), values) }
        else { StreamDiagnosticLogger.shared.record("recognition." + event, Self.redact(message), metadata: values) }
    }
    func error(_ event: String, _ message: String, _ error: Error, details: [String: String] = [:]) {
        guard enabled else { return }
        record(event, message, details.merging(Self.errorFields(error)) { _, new in new })
    }
    static func environment() -> [String: String] {
        var result = [
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "shazamServiceConfiguration": "App ID service cannot be verified at runtime"
        ]
        #if targetEnvironment(simulator)
        result["runtime"] = "simulator"
        #else
        result["runtime"] = "device-or-compatible-Mac"
        #endif
        return result
    }
    static func audioFormat(_ format: AVAudioFormat) -> [String: String] {
        let asbd = format.streamDescription.pointee
        return ["sampleRate": String(format.sampleRate), "channels": String(format.channelCount),
                "interleaved": String(format.isInterleaved), "commonFormat": String(format.commonFormat.rawValue),
                "formatID": String(asbd.mFormatID), "formatFlags": String(asbd.mFormatFlags),
                "bitsPerChannel": String(asbd.mBitsPerChannel), "bytesPerFrame": String(asbd.mBytesPerFrame)]
    }
    static func errorFields(_ error: Error) -> [String: String] {
        var result: [String: String] = [:]
        var seen = Set<ObjectIdentifier>()
        func visit(_ error: NSError, prefix: String, depth: Int) {
            guard depth < 5, seen.count < 12 else { result[prefix + "truncated"] = "true"; return }
            guard seen.insert(ObjectIdentifier(error)).inserted else { result[prefix + "cycle"] = "true"; return }
            result[prefix + "domain"] = redact(error.domain)
            result[prefix + "code"] = String(error.code)
            result[prefix + "description"] = redact(error.localizedDescription)
            if let value = error.localizedFailureReason { result[prefix + "failureReason"] = redact(value) }
            if let value = error.localizedRecoverySuggestion { result[prefix + "recoverySuggestion"] = redact(value) }
            if let value = error.userInfo[NSDebugDescriptionErrorKey] as? String { result[prefix + "debugDescription"] = redact(value) }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                visit(underlying, prefix: prefix + "underlying.", depth: depth + 1)
            }
            if let errors = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                for (index, child) in errors.prefix(5).enumerated() {
                    visit(child, prefix: prefix + "underlying\(index).", depth: depth + 1)
                }
            }
        }
        visit(error as NSError, prefix: "error.", depth: 0)
        return result
    }
    /// Retain the origin for diagnosis, never signed URL paths/query/fragment or
    /// user-info. Adapted from Autohop's bearer and key/value redaction rules.
    static func redact(_ text: String) -> String {
        var value = text
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:https?|file)://[^\s\"<>]+"#) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                let url = URLComponents(string: String(value[range]))
                let replacement = url?.scheme?.lowercased() == "file" ? "<file-url-redacted>"
                    : (url?.host.map { "[url-origin:\($0)]" } ?? "<url-redacted>")
                value.replaceSubrange(range, with: replacement)
            }
        }
        let rules = [
            (#"(?im)\b(authorization|cookie|set-cookie)\s*[:=]\s*[^\r\n]+"#, "$1=<redacted>"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*"#, "<jwt-redacted>"),
            (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-]+=*"#, "Bearer <redacted>"),
            (#"(?i)((?:authorization|auth|access[_-]?token|refresh[_-]?token|developer[_-]?token|token|api[_-]?key|x-api-key|key|secret|password|passwd|signature|sig|cookie|set-cookie|jwt)[\"']?\s*[:=]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s&,;{}]+)"#, "$1<redacted>")
        ]
        for (pattern, replacement) in rules {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return String(value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(1200))
    }
}
