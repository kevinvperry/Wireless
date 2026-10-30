import XCTest
import AVFoundation
import MediaToolbox
import ShazamKit

final class TapSongSamplesTests: XCTestCase {
    func testActualRenderCallbackFeedsTapSamplesWithoutChangingPlaybackOutput() throws {
        final class Source {
            let pcm: AVAudioPCMBuffer
            init(_ format: AVAudioFormat) {
                pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
                pcm.frameLength = 1024
                for channel in 0..<2 { for frame in 0..<1024 { pcm.floatChannelData![channel][frame] = 0.125 } }
            }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let state = VocalBoostTapState(level: .off)
        state.prepare(format: format.streamDescription.pointee, maximumFrames: 1024)
        state.songSamples.start()
        let source = Source(format)
        let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        destination.frameLength = 1024
        var frames: CMItemCount = 0
        var flags: MTAudioProcessingTapFlags = 0
        state.render(frames: 1024, flags: 0, buffers: destination.mutableAudioBufferList,
            framesOut: &frames, flagsOut: &flags, sourceContext: Unmanaged.passUnretained(source).toOpaque(),
            readSource: { context, requested, buffers, flags, written in
                let source = Unmanaged<Source>.fromOpaque(context).takeUnretainedValue()
                let input = UnsafeMutableAudioBufferListPointer(source.pcm.mutableAudioBufferList)
                let output = UnsafeMutableAudioBufferListPointer(buffers)
                for index in output.indices { memcpy(output[index].mData!, input[index].mData!, requested * MemoryLayout<Float>.size) }
                flags.pointee = 0; written.pointee = requested; return noErr
            })
        XCTAssertEqual(frames, 1024)
        XCTAssertEqual(destination.floatChannelData![0][0], 0.125)
        let batch = state.songSamples.drain()
        XCTAssertFalse(batch.discontinuity)
        let captured = try XCTUnwrap(batch.buffers.first)
        XCTAssertEqual(captured.frameLength, 1024)
        XCTAssertEqual(captured.floatChannelData![0][0], 0.125)
        XCTAssertNoThrow(try SHSignatureGenerator().append(captured, at: nil))
        XCTAssertGreaterThan(state.processedFrames.load(ordering: .relaxed), 0)
        state.songSamples.stop()
        state.unprepare()
    }

    func testCopiesOwnStorageAndPreservesPCMLayouts() throws {
        for interleaved in [false, true] {
            for type in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
                let format = try XCTUnwrap(AVAudioFormat(commonFormat: type, sampleRate: 48_000, channels: 2, interleaved: interleaved))
                let samples = TapSongSamples()
                samples.prepare(format: format, maximumFrames: 128)
                samples.start()
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
                pcm.frameLength = 128
                for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
                    memset(buffer.mData!, 0x12, Int(buffer.mDataByteSize))
                }
                samples.offer(pcm, discontinuity: true)
                let batch = samples.drain()
                XCTAssertFalse(batch.discontinuity)
                XCTAssertEqual(batch.buffers.count, 1)
                let saved = try XCTUnwrap(batch.buffers.first)
                for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) { memset(buffer.mData!, 0, Int(buffer.mDataByteSize)) }
                // Cycle both pools to ensure the delivered copy survives reuse.
                for _ in 0..<4 { samples.offer(pcm, discontinuity: false); _ = samples.drain() }
                for buffer in UnsafeMutableAudioBufferListPointer(saved.mutableAudioBufferList) {
                    XCTAssertEqual(buffer.mData!.load(as: UInt8.self), 0x12)
                }
                XCTAssertEqual(saved.frameLength, 128)
                XCTAssertEqual(saved.format, format)
                samples.stop()
                samples.offer(pcm, discontinuity: false)
                XCTAssertTrue(samples.drain().buffers.isEmpty)
            }
        }
    }

    func testOverflowAndDiscontinuityDiscardPartialAudio() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let samples = TapSongSamples()
        samples.prepare(format: format, maximumFrames: 128)
        samples.start()
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        pcm.frameLength = 128
        for _ in 0..<17 { samples.offer(pcm, discontinuity: false) }
        let overflow = samples.drain()
        XCTAssertTrue(overflow.discontinuity)
        XCTAssertTrue(overflow.buffers.isEmpty)
        samples.stop(); samples.start()
        samples.offer(pcm, discontinuity: true)
        XCTAssertFalse(samples.drain().discontinuity)
        samples.offer(pcm, discontinuity: true)
        XCTAssertTrue(samples.drain().discontinuity)
    }

    func testThreeSecondDeadlineAllowsOneFallbackAndResetsOnProgress() {
        var health = SongCaptureHealth(started: 0, fallbackAlreadyUsed: false)
        XCTAssertEqual(health.check(frames: 0, now: 2.9, sourceFailed: false), .continueCapture)
        XCTAssertEqual(health.check(frames: 0, now: 3, sourceFailed: false), .fallback)
        XCTAssertEqual(health.check(frames: 100, now: 5, sourceFailed: false), .continueCapture)
        XCTAssertEqual(health.check(frames: 100, now: 7.9, sourceFailed: false), .continueCapture)
        XCTAssertEqual(health.check(frames: 100, now: 8, sourceFailed: false), .fail)
        var direct = SongCaptureHealth(started: 0, fallbackAlreadyUsed: true)
        XCTAssertEqual(direct.check(frames: 0, now: 3, sourceFailed: false), .fail)
        var failedSource = SongCaptureHealth(started: 0, fallbackAlreadyUsed: false)
        XCTAssertEqual(failedSource.check(frames: 128, now: 0.1, sourceFailed: true), .fallback)
        XCTAssertEqual(failedSource.check(frames: 128, now: 0.2, sourceFailed: true), .fail)
    }
}
