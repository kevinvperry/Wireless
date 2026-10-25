import Foundation

/// Adapted from RadioStreamEngine's HLSPlaylist. The Vocal Boost fallback accepts
/// only unencrypted, whole ADTS AAC segments; other HLS stays with AVPlayer.
enum PackedAudioHLS {
    static func variant(in text: String, base: URL) -> URL? {
        guard text.contains("#EXT-X-STREAM-INF:") else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let tag = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }),
              tag + 1 < lines.count, !lines[tag + 1].hasPrefix("#") else { return nil }
        return URL(string: String(lines[tag + 1]), relativeTo: base)?.absoluteURL
    }

    static func segments(in text: String, base: URL) -> [(sequence: Int, url: URL)]? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "#EXTM3U",
              !lines.contains(where: { $0.hasPrefix("#EXT-X-MAP:") || $0.hasPrefix("#EXT-X-BYTERANGE:")
                  || ($0.hasPrefix("#EXT-X-KEY:") && !$0.hasPrefix("#EXT-X-KEY:METHOD=NONE")) }),
              let line = lines.first(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }),
              let first = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)), first >= 0 else { return nil }
        var result: [(Int, URL)] = []
        for line in lines where !line.hasPrefix("#") && !line.isEmpty {
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  first <= Int.max - result.count else { return nil }
            result.append((first + result.count, url))
        }
        return result.isEmpty ? nil : result
    }

    static func audio(in data: Data) -> Data? {
        var offset = 0
        // Adapted from RadioStreamEngine.stripLeadingID3; cope with multiple tags.
        while data.count - offset >= 10, data[offset..<offset + 3].elementsEqual([0x49, 0x44, 0x33]) {
            let size = data[offset + 6..<offset + 10].reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
            let end = offset + 10 + size + ((data[offset + 5] & 0x10) != 0 ? 10 : 0)
            guard end < data.count else { return nil }
            offset = end
        }
        guard data.count - offset >= 7, data[offset] == 0xff, data[offset + 1] & 0xf6 == 0xf0 else { return nil }
        return Data(data.dropFirst(offset))
    }
}
