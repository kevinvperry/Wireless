import XCTest

final class PackedAudioHLSTests: XCTestCase {
    private let base = URL(string: "https://example.test/live/index.m3u8")!

    func testPlaylistResolvesSequencesAndRelativeSegments() throws {
        let playlist = "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:42\n#EXTINF:2,\nfirst.aac\n#EXTINF:2,\nsecond.aac\n"
        let segments = try XCTUnwrap(PackedAudioHLS.segments(in: playlist, base: base))
        XCTAssertEqual(segments.map(\.sequence), [42, 43])
        XCTAssertEqual(segments.last?.url.absoluteString, "https://example.test/live/second.aac")
        XCTAssertEqual(PackedAudioHLS.variant(in: "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000\naudio/index.m3u8", base: base)?.absoluteString,
                       "https://example.test/live/audio/index.m3u8")
    }

    func testFallbackRejectsEncryptedFragmentedAndByteRangeMedia() {
        for tag in ["#EXT-X-KEY:METHOD=AES-128,URI=\"key\"", "#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"",
                    "#EXT-X-MAP:URI=\"init.mp4\"", "#EXT-X-BYTERANGE:1000@0"] {
            XCTAssertNil(PackedAudioHLS.segments(in: "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:0\n\(tag)\nsegment.aac", base: base))
        }
    }

    func testAACValidationStripsMetadataAndRejectsOtherContainers() {
        let aac = Data([0xff, 0xf1, 0x50, 0x80, 0, 0xff, 0xfc])
        XCTAssertEqual(PackedAudioHLS.audio(in: aac), aac)
        let tag = Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 1, 0])
        XCTAssertEqual(PackedAudioHLS.audio(in: tag + tag + aac), aac)
        XCTAssertNil(PackedAudioHLS.audio(in: tag))
        XCTAssertNil(PackedAudioHLS.audio(in: Data(repeating: 0x47, count: 188)))
        XCTAssertNil(PackedAudioHLS.audio(in: Data("not audio".utf8)))
    }
}
