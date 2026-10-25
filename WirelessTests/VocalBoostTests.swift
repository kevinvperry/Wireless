import XCTest
import AVFoundation
import MediaToolbox

final class VocalBoostTests: XCTestCase {
    func testConcurrentTapCleanupAndRenderingDoNotUseDisposedUnits() throws {
        final class RenderContext: @unchecked Sendable {
            let state = VocalBoostTapState(level: .strong)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        }
        let context = RenderContext()
        context.state.prepare(format: context.format.streamDescription.pointee, maximumFrames: 256)
        let complete = DispatchGroup()
        complete.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let pcm = AVAudioPCMBuffer(pcmFormat: context.format, frameCapacity: 256)!
            pcm.frameLength = 256
            for index in 0..<6_000 {
                for channel in 0..<2 {
                    for frame in 0..<256 { pcm.floatChannelData![channel][frame] = 0.1 }
                }
                context.state.process(pcm.mutableAudioBufferList, frames: 256, discontinuity: index.isMultiple(of: 4))
            }
            complete.leave()
        }
        complete.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<150 {
                context.state.unprepare()
                context.state.prepare(format: context.format.streamDescription.pointee, maximumFrames: 256)
            }
            complete.leave()
        }
        XCTAssertEqual(complete.wait(timeout: .now() + 20), .success)
        context.state.unprepare()
    }

    func testLiveTapPresetChangesAndOffBypassUseTheSamePreparedGraph() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let state = VocalBoostTapState(level: .standard)
        state.prepare(format: format.streamDescription.pointee, maximumFrames: 1_024)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        pcm.frameLength = 1_024
        let initialPreparations = state.prepareCount.load(ordering: .relaxed)
        for _ in 0..<20 {
            for (level, bass) in [(VocalBoostLevel.light, false), (.strong, false), (.off, true), (.off, false)] {
                state.setPreset(level, deepBass: bass)
                XCTAssertFalse(state.hasAppliedPreset)
                for channel in 0..<2 {
                    for frame in 0..<1_024 { pcm.floatChannelData![channel][frame] = 0.125 }
                }
                state.process(pcm.mutableAudioBufferList, frames: 1_024, discontinuity: false)
                XCTAssertTrue(state.hasAppliedPreset)
                XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
                XCTAssertEqual(state.prepareCount.load(ordering: .relaxed), initialPreparations)
                if level == .off, !bass {
                    for channel in 0..<2 {
                        XCTAssertTrue((0..<1_024).allSatisfy { pcm.floatChannelData![channel][$0] == 0.125 }, "Off must bypass the existing graph without altering the original PCM")
                    }
                }
            }
        }
    }

    func testRepeatedStartFlagsCannotReprimeLatencyForever() throws {
        final class Source {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
            let pcm: AVAudioPCMBuffer
            var calls = 0
            var framesRead = 0
            init() {
                pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                pcm.frameLength = 1_024
            }
        }
        let source = Source()
        let state = VocalBoostTapState(level: .standard)
        state.prepare(format: source.format.streamDescription.pointee, maximumFrames: 1_024)
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: 1_024))
        output.frameLength = 1_024
        var framesOut = 0
        var flagsOut: MTAudioProcessingTapFlags = 0
        state.render(frames: 1_024, flags: kMTAudioProcessingTapFlag_StartOfStream,
            buffers: output.mutableAudioBufferList, framesOut: &framesOut, flagsOut: &flagsOut,
            sourceContext: Unmanaged.passUnretained(source).toOpaque(), readSource: { context, count, buffers, flags, produced in
                let source = Unmanaged<Source>.fromOpaque(context).takeUnretainedValue()
                source.calls += 1
                guard source.calls < 64 else { produced.pointee = 0; return noErr }
                source.framesRead += count
                let input = UnsafeMutableAudioBufferListPointer(source.pcm.mutableAudioBufferList)
                let output = UnsafeMutableAudioBufferListPointer(buffers)
                for channel in input.indices {
                    for frame in 0..<count { source.pcm.floatChannelData![channel][frame] = 0.125 }
                    output[channel] = input[channel]
                    output[channel].mDataByteSize = UInt32(count) * 4
                }
                // Native HLS can repeat this bit on each look-ahead source read.
                flags.pointee = kMTAudioProcessingTapFlag_StartOfStream
                produced.pointee = count
                return noErr
            })
        XCTAssertEqual(framesOut, 1_024, "A single processing callback must return audio rather than consume its source forever")
        XCTAssertLessThan(source.calls, 64)
        XCTAssertLessThanOrEqual(source.framesRead, 49_024)
        XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
    }

    func testHLSSupportDependsOnOSAndDirectStreamsRemainSupported() {
        XCTAssertNotNil(VocalBoostState.unsupportedReason(format: "hls", supportsHLSTap: false))
        XCTAssertNil(VocalBoostState.unsupportedReason(format: "hls", supportsHLSTap: true))
        for format in ["aac", "mp3"] {
            XCTAssertNil(VocalBoostState.unsupportedReason(format: format, supportsHLSTap: false))
        }
        XCTAssertNotNil(VocalBoostState.unsupportedReason(format: nil, supportsHLSTap: true))
        XCTAssertNotNil(VocalBoostState.unsupportedReason(format: "unknown", supportsHLSTap: true))
        XCTAssertFalse(VocalBoostState.preparing.isActive)
        XCTAssertFalse(VocalBoostState.unavailable("Protected").isActive)
    }

    private func render(level: VocalBoostLevel, frequency: Double, amplitude: Double,
                        sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2,
                        interleaved: Bool = false, deepBass: Bool = false) throws -> (rms: Double, peak: Double) {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate, channels: channels, interleaved: interleaved))
        let state = VocalBoostTapState(level: level, deepBass: deepBass)
        state.prepare(format: format.streamDescription.pointee, maximumFrames: 1_024)
        XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        buffer.frameLength = 1_024
        var energy = 0.0, peak = 0.0, samples = 0
        for block in 0..<120 {
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for audioBuffer in buffers {
                let data = try XCTUnwrap(audioBuffer.mData).assumingMemoryBound(to: Float.self)
                let stride = Int(audioBuffer.mNumberChannels)
                for frame in 0..<1_024 {
                    let value = Float(amplitude * sin(2 * .pi * frequency * Double(block * 1_024 + frame) / sampleRate))
                    for channel in 0..<stride { data[frame * stride + channel] = value }
                }
            }
            state.process(buffer.mutableAudioBufferList, frames: 1_024, discontinuity: block == 0)
            XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
            if block > 20 { // Exclude filter/compressor settling and effect latency.
                for audioBuffer in buffers {
                    let data = audioBuffer.mData!.assumingMemoryBound(to: Float.self)
                    for index in 0..<Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size {
                        let value = Double(data[index])
                        XCTAssertTrue(value.isFinite)
                        energy += value * value; peak = max(peak, abs(value)); samples += 1
                    }
                }
            }
        }
        XCTAssertEqual(state.processedFrames.load(ordering: .relaxed), 120 * 1_024)
        return (sqrt(energy / Double(samples)), peak)
    }

    func testDeepBassLiftsLowFrequenciesWithoutSpeechFiltering() throws {
        for rate in [44_100.0, 48_000.0] {
            let bass = try render(level: .off, frequency: 40, amplitude: 0.1, sampleRate: rate, deepBass: true)
            let mid = try render(level: .off, frequency: 1_000, amplitude: 0.1, sampleRate: rate, deepBass: true)
            let lift = 20 * log10(bass.rms / mid.rms)
            XCTAssertGreaterThan(lift, 3)
            XCTAssertLessThan(lift, 6)
            // Deep Bass takes precedence defensively, even if a caller passes a
            // speech level: the 180 Hz speech high-pass must never cancel it.
            let conflicting = try render(level: .strong, frequency: 40, amplitude: 0.1, sampleRate: rate, deepBass: true)
            XCTAssertEqual(conflicting.rms, bass.rms, accuracy: 0.001)
        }
    }

    func testDeepBassPreservesPeakHeadroomAndStereoFormats() throws {
        for channels: AVAudioChannelCount in [1, 2] {
            for interleaved in [false, true] {
                let result = try render(level: .off, frequency: 60, amplitude: 0.99,
                                        channels: channels, interleaved: interleaved, deepBass: true)
                XCTAssertLessThanOrEqual(result.peak, 1.01)
                XCTAssertGreaterThan(result.rms, 0.3)
            }
        }
    }

    func testDeepBassModePersistsWithoutBecomingVocalBoost() throws {
        let data = try JSONEncoder().encode(WirelessListeningMode.deepBass)
        XCTAssertEqual(try JSONDecoder().decode(WirelessListeningMode.self, from: data), .deepBass)
        XCTAssertEqual(WirelessListeningMode.deepBass.title, "Deep Bass")
        XCTAssertNotEqual(WirelessListeningMode.deepBass, .vocalBoost)
    }

    func testLightRemovesLowFrequencyRumbleWhileRetainingSpeechBand() throws {
        let rumble = try render(level: .light, frequency: 50, amplitude: 0.1)
        let speech = try render(level: .light, frequency: 1_000, amplitude: 0.1)
        XCTAssertLessThan(rumble.rms, speech.rms * 0.2)
        XCTAssertGreaterThan(speech.rms, 0.07)
    }

    func testAllLevelsLimitLoudPeaksAndHandleMonoStereoAndSampleRates() throws {
        for level in [VocalBoostLevel.light, .standard, .strong] {
            for rate in [44_100.0, 48_000.0] {
                for channels: AVAudioChannelCount in [1, 2] {
                    let output = try render(level: level, frequency: 1_000, amplitude: 0.95,
                                            sampleRate: rate, channels: channels)
                    XCTAssertLessThanOrEqual(output.peak, 1.01, "\(level), \(rate), \(channels)")
                    XCTAssertGreaterThan(output.rms, 0.01)
                }
            }
        }
    }

    func testInterleavedFormatAndRepreparation() throws {
        let output = try render(level: .standard, frequency: 700, amplitude: 0.1, interleaved: true)
        XCTAssertGreaterThan(output.rms, 0.01)
        let state = VocalBoostTapState(level: .strong)
        state.prepare(format: AudioStreamBasicDescription(), maximumFrames: 1_024)
        XCTAssertNotEqual(state.failure.load(ordering: .relaxed), 0)
        let valid = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        state.prepare(format: valid.streamDescription.pointee, maximumFrames: 1_024)
        XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
        state.unprepare()
        state.unprepare()
    }

    func testIntegerPCMConversionAndFailedProcessingPreserveBroadcast() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16,
            sampleRate: 48_000, channels: 2, interleaved: true))
        let state = VocalBoostTapState(level: .standard)
        state.prepare(format: format.streamDescription.pointee, maximumFrames: 1_024)
        XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048))
        buffer.frameLength = 1_024
        let data = try XCTUnwrap(buffer.int16ChannelData)[0]
        for i in 0..<2_048 { data[i] = Int16(1_000 * sin(Double(i) * 0.1)) }
        state.process(buffer.mutableAudioBufferList, frames: 1_024, discontinuity: true)
        XCTAssertEqual(state.failure.load(ordering: .relaxed), 0)
        XCTAssertEqual(state.processedFrames.load(ordering: .relaxed), 1_024)
        buffer.frameLength = 2_048
        for i in 0..<4_096 { data[i] = 123 }
        state.process(buffer.mutableAudioBufferList, frames: 2_048, discontinuity: false)
        XCTAssertNotEqual(state.failure.load(ordering: .relaxed), 0)
        XCTAssertTrue((0..<4_096).allSatisfy { data[$0] == 123 }, "A failed effect must leave original audio intact")
    }

    func testCompressionImprovesQuietSpeechAtMatchedLoudness() throws {
        let lightQuiet = try render(level: .light, frequency: 1_000, amplitude: 0.01)
        let lightLoud = try render(level: .light, frequency: 1_000, amplitude: 0.5)
        let strongQuiet = try render(level: .strong, frequency: 1_000, amplitude: 0.01)
        let strongLoud = try render(level: .strong, frequency: 1_000, amplitude: 0.5)
        // Match the loud sections before comparing quiet sections. A uniform
        // volume increase cannot pass this speech-levelling check.
        let matchedQuiet = strongQuiet.rms * lightLoud.rms / strongLoud.rms
        XCTAssertGreaterThan(matchedQuiet, lightQuiet.rms * 1.2)
    }
}
