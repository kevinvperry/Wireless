// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Uses the Autohop / Pocket Casts-derived VocalBoostConfiguration.

import AVFoundation
import AudioToolbox
import MediaToolbox
import Synchronization

/// Processes AVPlayer's mixed HLS output without replacing its network,
/// buffering, metadata or route handling. FairPlay audio cannot be tapped.
final class HLSVocalBoostTap {
    let state: VocalBoostTapState
    private let tap: MTAudioProcessingTap

    @available(iOS 27.0, *)
    init(level: VocalBoostLevel, musicPreset: MusicPreset = .off) throws {
        state = VocalBoostTapState(level: level, musicPreset: musicPreset)
        let retained = Unmanaged.passRetained(state).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained,
            init: { _, client, storage in storage.pointee = client },
            finalize: { tap in
                Unmanaged<VocalBoostTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maximumFrames, format in
                let state = Unmanaged<VocalBoostTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                state.prepare(format: format.pointee, maximumFrames: maximumFrames)
            },
            unprepare: { tap in
                Unmanaged<VocalBoostTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().unprepare()
            },
            process: { tap, frames, flags, buffers, framesOut, flagsOut in
                let state = Unmanaged<VocalBoostTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                state.render(tap: tap, frames: frames, flags: flags, buffers: buffers,
                             framesOut: framesOut, flagsOut: flagsOut)
            }
        )
        var created: MTAudioProcessingTap?
        // A preferred float format simplifies the common case. prepare still
        // validates the actual format, which Apple is permitted to change.
        let preferred = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let status = MTAudioProcessingTapCreateWithPreferredFormat(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects,
            preferred.formatDescription, &created
        )
        guard status == noErr, let created else {
            Unmanaged<VocalBoostTapState>.fromOpaque(retained).release()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        tap = created
    }

    func setLevel(_ level: VocalBoostLevel, musicPreset: MusicPreset) {
        state.setPreset(level, musicPreset: musicPreset)
    }

    @MainActor
    @available(iOS 27.0, *)
    func attach(to item: AVPlayerItem) {
        let parameters = AVMutableAudioMixInputParameters()
        // Apple's special mixed-track ID, introduced alongside HLS taps in iOS 27.
        parameters.trackID = AVAudioMixInputParametersTrackID.mixID.rawValue
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }
}

/// AVFoundation can call unprepare on its cleanup queue while a processing
/// callback is in flight (including server-connection teardown). The audio
/// callback only tries the lifecycle lock: it passes through original audio
/// rather than waiting. Preparation/cleanup may wait for an in-flight render.
final class VocalBoostTapState {
    private let lifecycleLock = NSLock()
    let prepareCount = Atomic<Int>(0)
    let failure = Atomic<OSStatus>(noErr)
    let processedFrames = Atomic<Int64>(0)
    private let requestedPreset: Atomic<Int>
    private let appliedPreset = Atomic<Int>(-1)
    private var configuredPreset = -1
    // Allocate parameter tables before callbacks; applying a preset only reads them.
    private let presets: [[[(AudioUnitParameterID, Float)]]]
    var hasAppliedPreset: Bool {
        appliedPreset.load(ordering: .acquiring) == requestedPreset.load(ordering: .acquiring)
    }
    private var units: [AudioUnit] = []
    private var delivery: AVAudioPCMBuffer?
    private var latencyFrames: UInt32 = 0
    private var pendingLatencyFrames: UInt32 = 0
    private var tapBytesPerFrame: UInt32 = 0
    private var scratch: AVAudioPCMBuffer?
    private var convertedInput: AVAudioPCMBuffer?
    private var convertedOutput: AVAudioPCMBuffer?
    private var inputConverter: AudioConverterRef?
    private var outputConverter: AudioConverterRef?
    private var source: UnsafeMutablePointer<AudioBufferList>?
    private var maximumFrames: UInt32 = 0
    private var bytesPerFrame: UInt32 = 0
    private var sampleTime: Float64 = 0

    init(level: VocalBoostLevel, musicPreset: MusicPreset = .off) {
        requestedPreset = Atomic(Self.presetIndex(level, musicPreset: musicPreset))
        let choices = VocalBoostLevel.allCases.map { ($0, MusicPreset.off) }
            + MusicPreset.allCases.filter { $0 != .off }.map { (VocalBoostLevel.off, $0) }
        presets = choices.map { level, music in
            VocalBoostConfiguration.subtypes.map {
                VocalBoostConfiguration.parameters(for: $0, level: level, musicPreset: music)
            }
        }
    }

    private static func presetIndex(_ level: VocalBoostLevel, musicPreset: MusicPreset) -> Int {
        musicPreset == .off ? VocalBoostLevel.allCases.firstIndex(of: level)!
            : VocalBoostLevel.allCases.count + MusicPreset.allCases.firstIndex(of: musicPreset)! - 1
    }

    func setPreset(_ level: VocalBoostLevel, musicPreset: MusicPreset) {
        requestedPreset.store(Self.presetIndex(level, musicPreset: musicPreset), ordering: .releasing)
    }
    deinit { unprepare() }

    func prepare(format: AudioStreamBasicDescription, maximumFrames: CMItemCount) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        unprepareGraph()
        prepareCount.wrappingAdd(1, ordering: .relaxed)
        failure.store(noErr, ordering: .relaxed)
        processedFrames.store(0, ordering: .relaxed)
        var format = format
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate > 0, format.mChannelsPerFrame > 0,
              maximumFrames > 0, maximumFrames <= Int(UInt32.max),
              let audioFormat = AVAudioFormat(streamDescription: &format),
              let scratch = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: UInt32(maximumFrames)) else {
            failure.store(kAudio_ParamError, ordering: .relaxed)
            return
        }
        let capacity = UInt32(maximumFrames)
        let workingFormat = AVAudioFormat(standardFormatWithSampleRate: format.mSampleRate,
                                          channels: format.mChannelsPerFrame)!
        var working = workingFormat.streamDescription.pointee
        guard let input = AVAudioPCMBuffer(pcmFormat: workingFormat, frameCapacity: capacity),
              let output = AVAudioPCMBuffer(pcmFormat: workingFormat, frameCapacity: capacity) else {
            failure.store(kAudio_MemFullError, ordering: .relaxed)
            return
        }
        guard let delivery = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: capacity) else {
            failure.store(kAudio_MemFullError, ordering: .relaxed)
            return
        }
        self.delivery = delivery
        tapBytesPerFrame = format.mBytesPerFrame
        convertedInput = input
        self.scratch = output
        convertedOutput = scratch
        self.maximumFrames = capacity
        bytesPerFrame = working.mBytesPerFrame
        sampleTime = 0
        do {
            // Same-rate PCM converters handle the numeric type and channel layout
            // actually delivered by Apple, even if it differs from our preference.
            try check(AudioConverterNew(&format, &working, &inputConverter))
            try check(AudioConverterNew(&working, &format, &outputConverter))
            for subtype in VocalBoostConfiguration.subtypes {
                // Connect every stage once. Preset changes bypass/configure units
                // on the render thread, never rebuild or dispose a live graph.
                let parameters = VocalBoostConfiguration.parameters(for: subtype, level: .standard,
                    musicPreset: subtype == kAudioUnitSubType_LowShelfFilter ? .deep : .off)
                var description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                    componentSubType: subtype, componentManufacturer: kAudioUnitManufacturer_Apple,
                    componentFlags: 0, componentFlagsMask: 0)
                guard let component = AudioComponentFindNext(nil, &description) else { throw TapError.status(kAudio_ParamError) }
                var instance: AudioUnit?
                try check(AudioComponentInstanceNew(component, &instance))
                guard let unit = instance else { throw TapError.status(kAudio_ParamError) }
                // Retain every created unit immediately so failures also dispose it.
                units.append(unit)
                var limit = self.maximumFrames
                try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice,
                    kAudioUnitScope_Global, 0, &limit, UInt32(MemoryLayout<UInt32>.size)))
                for scope in [kAudioUnitScope_Input, kAudioUnitScope_Output] {
                    try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                        scope, 0, &working, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
                }
                if units.count > 1 {
                    var connection = AudioUnitConnection(sourceAudioUnit: units[units.count - 2], sourceOutputNumber: 0, destInputNumber: 0)
                    try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MakeConnection,
                        kAudioUnitScope_Input, 0, &connection, UInt32(MemoryLayout<AudioUnitConnection>.size)))
                } else {
                    var callback = AURenderCallbackStruct(inputProc: { context, _, _, _, frames, data in
                        guard let data else { return kAudio_ParamError }
                        return Unmanaged<VocalBoostTapState>.fromOpaque(context).takeUnretainedValue().provideInput(data, frames: frames)
                    }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
                    try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                        kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
                }
                for (parameter, value) in parameters {
                    try check(AudioUnitSetParameter(unit, parameter, kAudioUnitScope_Global, 0, value, 0))
                }
                try check(AudioUnitInitialize(unit))
            }
            try applyRequestedPreset()
            var latency: Float64 = 0
            for unit in units {
                var seconds: Float64 = 0
                var size = UInt32(MemoryLayout<Float64>.size)
                try check(AudioUnitGetProperty(unit, kAudioUnitProperty_Latency,
                    kAudioUnitScope_Global, 0, &seconds, &size))
                latency += seconds
            }
            guard latency.isFinite, latency >= 0, latency <= 1 else { throw TapError.status(kAudio_ParamError) }
            latencyFrames = UInt32(ceil(latency * format.mSampleRate))
            pendingLatencyFrames = latencyFrames
        } catch {
            unprepareGraph()
            failure.store((error as? TapError)?.code ?? kAudio_ParamError, ordering: .relaxed)
        }
    }

    func unprepare() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        unprepareGraph()
    }

    private func unprepareGraph() {
        configuredPreset = -1
        appliedPreset.store(-1, ordering: .releasing)
        for unit in units.reversed() {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        units.removeAll()
        scratch = nil; delivery = nil
        latencyFrames = 0; pendingLatencyFrames = 0
        convertedInput = nil; convertedOutput = nil
        if let inputConverter { AudioConverterDispose(inputConverter) }
        if let outputConverter { AudioConverterDispose(outputConverter) }
        inputConverter = nil; outputConverter = nil
        source = nil
    }

    private func applyRequestedPreset() throws {
        let preset = requestedPreset.load(ordering: .acquiring)
        guard preset != configuredPreset else { return }
        guard units.count == VocalBoostConfiguration.subtypes.count else { throw TapError.status(kAudio_ParamError) }
        // Restore unity limiter gain first when switching to bass; restore speech gain
        // after disabling its conflicting shelf when switching back.
        let first = preset >= 4 ? units.count - 1 : 0
        for offset in 0..<units.count {
            let index = (first + offset) % units.count
            let parameters = presets[preset][index]
            for (parameter, value) in parameters {
                try check(AudioUnitSetParameter(units[index], parameter, kAudioUnitScope_Global, 0, value, 0))
            }
            var bypass: UInt32 = parameters.isEmpty ? 1 : 0
            try check(AudioUnitSetProperty(units[index], kAudioUnitProperty_BypassEffect,
                kAudioUnitScope_Global, 0, &bypass, UInt32(MemoryLayout<UInt32>.size)))
        }
        configuredPreset = preset
        appliedPreset.store(preset, ordering: .releasing)
    }

    /// Absorb the Audio Units' look-ahead latency as required by the tap API.
    /// Pull extra source samples at each start/discontinuity, discard the initial
    /// delayed output, then deliver the requested frame count from preallocated memory.
    typealias SourceReader = @convention(c) (UnsafeMutableRawPointer, CMItemCount,
        UnsafeMutablePointer<AudioBufferList>, UnsafeMutablePointer<MTAudioProcessingTapFlags>,
        UnsafeMutablePointer<CMItemCount>) -> OSStatus

    func render(tap: MTAudioProcessingTap, frames: CMItemCount, flags: MTAudioProcessingTapFlags,
                buffers: UnsafeMutablePointer<AudioBufferList>, framesOut: UnsafeMutablePointer<CMItemCount>,
                flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
        render(frames: frames, flags: flags, buffers: buffers, framesOut: framesOut, flagsOut: flagsOut,
            sourceContext: Unmanaged.passUnretained(tap).toOpaque(), readSource: { context, count, data, flags, produced in
                let tap = Unmanaged<MTAudioProcessingTap>.fromOpaque(context).takeUnretainedValue()
                return MTAudioProcessingTapGetSourceAudio(tap, count, data, flags, nil, produced)
            })
    }

    // A C function pointer keeps the production callback allocation-free and
    // allows deterministic tests of native source flags and partial reads.
    func render(frames: CMItemCount, flags: MTAudioProcessingTapFlags,
                buffers: UnsafeMutablePointer<AudioBufferList>, framesOut: UnsafeMutablePointer<CMItemCount>,
                flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>, sourceContext: UnsafeMutableRawPointer,
                readSource: SourceReader) {
        guard lifecycleLock.try() else {
            let status = readSource(sourceContext, frames, buffers, flagsOut, framesOut)
            if status != noErr { framesOut.pointee = 0 }
            return
        }
        defer { lifecycleLock.unlock() }
        guard let delivery, frames > 0, frames <= maximumFrames,
              failure.load(ordering: .relaxed) == noErr else {
            let status = readSource(sourceContext, frames, buffers, flagsOut, framesOut)
            if status != noErr { framesOut.pointee = 0; failure.store(status, ordering: .relaxed) }
            return
        }
        if (flags & kMTAudioProcessingTapFlag_StartOfStream) != 0 { pendingLatencyFrames = latencyFrames }
        delivery.frameLength = UInt32(frames)
        let output = UnsafeMutableAudioBufferListPointer(delivery.mutableAudioBufferList)
        var written: UInt32 = 0
        flagsOut.pointee = 0
        var firstPull = true
        var pulledFrames: UInt64 = 0
        let frameBudget = UInt64(frames) + UInt64(latencyFrames)
        while written < frames, pulledFrames < frameBudget {
            let request = CMItemCount(min(UInt64(maximumFrames), UInt64(frames) - UInt64(written) + UInt64(pendingLatencyFrames)))
            var received: CMItemCount = 0
            var sourceFlags: MTAudioProcessingTapFlags = 0
            let status = readSource(sourceContext, request, buffers, &sourceFlags, &received)
            guard status == noErr, received > 0 else {
                if status != noErr { failure.store(status, ordering: .relaxed) }
                flagsOut.pointee |= sourceFlags
                break
            }
            // A native source can repeat StartOfStream on look-ahead pulls in
            // this callback. Re-priming on every pull consumes audio indefinitely
            // and returns no frames, starving AVPlayer and its media server.
            guard received <= request else { failure.store(kAudio_ParamError, ordering: .relaxed); break }
            pulledFrames += UInt64(received)
            let discontinuity = firstPull && ((sourceFlags | flags) & kMTAudioProcessingTapFlag_StartOfStream) != 0
            if discontinuity { pendingLatencyFrames = latencyFrames }
            // Reset at source discontinuities; subsequent continuous pulls retain DSP state.
            processGraph(buffers, frames: UInt32(received), discontinuity: discontinuity)
            firstPull = false
            let discard = failure.load(ordering: .relaxed) == noErr ? min(pendingLatencyFrames, UInt32(received)) : 0
            pendingLatencyFrames -= discard
            let count = min(UInt32(received) - discard, UInt32(frames) - written)
            let input = UnsafeMutableAudioBufferListPointer(buffers)
            guard input.count == output.count else { failure.store(kAudio_ParamError, ordering: .relaxed); break }
            for index in input.indices {
                if let from = input[index].mData, let to = output[index].mData {
                    memcpy(to.advanced(by: Int(written * tapBytesPerFrame)),
                           from.advanced(by: Int(discard * tapBytesPerFrame)), Int(count * tapBytesPerFrame))
                }
            }
            written += count
            flagsOut.pointee |= sourceFlags
            if (sourceFlags & kMTAudioProcessingTapFlag_EndOfStream) != 0 { break }
        }
        let destination = UnsafeMutableAudioBufferListPointer(buffers)
        if destination.count == output.count {
            for index in output.indices {
                destination[index] = output[index]
                destination[index].mDataByteSize = written * tapBytesPerFrame
            }
        }
        framesOut.pointee = CMItemCount(written)
    }

    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: UInt32, discontinuity: Bool) {
        guard lifecycleLock.try() else { return }
        defer { lifecycleLock.unlock() }
        processGraph(buffers, frames: frames, discontinuity: discontinuity)
    }

    private func processGraph(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: UInt32, discontinuity: Bool) {
        guard frames > 0, failure.load(ordering: .relaxed) == noErr,
              let last = units.last, let scratch, let convertedInput, let convertedOutput,
              let inputConverter, let outputConverter else { return }
        guard frames <= maximumFrames else {
            failure.store(kAudioUnitErr_TooManyFramesToProcess, ordering: .relaxed)
            return
        }
        do { try applyRequestedPreset() }
        catch { failure.store((error as? TapError)?.code ?? kAudio_ParamError, ordering: .relaxed); return }
        if discontinuity {
            for unit in units { AudioUnitReset(unit, kAudioUnitScope_Global, 0) }
            sampleTime = 0
        }
        scratch.frameLength = frames
        convertedInput.frameLength = frames
        convertedOutput.frameLength = frames
        let conversion = AudioConverterConvertComplexBuffer(inputConverter, frames, buffers, convertedInput.mutableAudioBufferList)
        guard conversion == noErr else { failure.store(conversion, ordering: .relaxed); return }
        source = convertedInput.mutableAudioBufferList
        defer { source = nil }
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = sampleTime
        timestamp.mFlags = .sampleTimeValid
        var flags: AudioUnitRenderActionFlags = []
        let status = AudioUnitRender(last, &flags, &timestamp, 0, frames, scratch.mutableAudioBufferList)
        sampleTime += Double(frames)
        guard status == noErr else {
            // Render into scratch so a failed unit cannot corrupt the broadcast.
            failure.store(status, ordering: .relaxed)
            return
        }
        let outputConversion = AudioConverterConvertComplexBuffer(outputConverter, frames,
            scratch.audioBufferList, convertedOutput.mutableAudioBufferList)
        guard outputConversion == noErr else { failure.store(outputConversion, ordering: .relaxed); return }
        let output = UnsafeMutableAudioBufferListPointer(buffers)
        let processed = UnsafeMutableAudioBufferListPointer(convertedOutput.mutableAudioBufferList)
        guard output.count == processed.count else {
            failure.store(kAudio_ParamError, ordering: .relaxed)
            return
        }
        for index in output.indices {
            guard output[index].mDataByteSize >= processed[index].mDataByteSize,
                  output[index].mData != nil, processed[index].mData != nil else {
                failure.store(kAudio_ParamError, ordering: .relaxed)
                return
            }
        }
        for index in output.indices {
            memcpy(output[index].mData!, processed[index].mData!, Int(processed[index].mDataByteSize))
        }
        processedFrames.wrappingAdd(Int64(frames), ordering: .relaxed)
    }

    private func provideInput(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: UInt32) -> OSStatus {
        guard let source, frames <= maximumFrames else { return kAudio_ParamError }
        let input = UnsafeMutableAudioBufferListPointer(source)
        let output = UnsafeMutableAudioBufferListPointer(buffers)
        guard input.count == output.count else { return kAudio_ParamError }
        let bytes = frames * bytesPerFrame
        for index in input.indices {
            guard input[index].mDataByteSize >= bytes, let data = input[index].mData else { return kAudio_ParamError }
            if let destination = output[index].mData {
                guard output[index].mDataByteSize >= bytes else { return kAudio_ParamError }
                memcpy(destination, data, Int(bytes))
            } else { output[index].mData = data }
            output[index].mDataByteSize = bytes
        }
        return noErr
    }

    private enum TapError: Error {
        case status(OSStatus)
        var code: OSStatus { switch self { case .status(let code): return code } }
    }
    private func check(_ status: OSStatus) throws {
        if status != noErr { throw TapError.status(status) }
    }
}
