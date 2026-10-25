// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Adapted via Autohop from Pocket Casts for iOS, Automattic, Inc. and contributors.

import AVFoundation
import AudioToolbox

/// Matches Autohop's user-facing Vocal Boost levels.
enum VocalBoostLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, light, standard, strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Autohop's Vocal Boost DSP graph, adapted for Wireless's decoded live PCM.
/// The signal-chain values originate from Pocket Casts and remain MPL-2.0 code.
final class VocalBoostProcessor {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    private let lowShelf: AVAudioUnitEffect
    private let highPass: AVAudioUnitEffect
    private let dynamics: AVAudioUnitEffect
    private let limiter: AVAudioUnitEffect

    init(format: AVAudioFormat, level: VocalBoostLevel, deepBass: Bool = false) throws {
        lowShelf = Self.makeAudioUnit(subType: kAudioUnitSubType_LowShelfFilter)
        highPass = Self.makeAudioUnit(subType: kAudioUnitSubType_HighPassFilter)
        dynamics = Self.makeAudioUnit(subType: kAudioUnitSubType_DynamicsProcessor)
        limiter = Self.makeAudioUnit(subType: kAudioUnitSubType_PeakLimiter)

        engine.attach(player)
        engine.attach(lowShelf)
        engine.attach(highPass)
        engine.attach(dynamics)
        engine.attach(limiter)
        if #available(iOS 27.0, *) {
            try engine.connectNode(player, to: lowShelf, format: format)
            try engine.connectNode(lowShelf, to: highPass, format: format)
            try engine.connectNode(highPass, to: dynamics, format: format)
            try engine.connectNode(dynamics, to: limiter, format: format)
            try engine.connectNode(limiter, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(player, to: lowShelf, format: format)
            engine.connect(lowShelf, to: highPass, format: format)
            engine.connect(highPass, to: dynamics, format: format)
            engine.connect(dynamics, to: limiter, format: format)
            engine.connect(limiter, to: engine.mainMixerNode, format: format)
        }
        try configure(level, deepBass: deepBass)
        try engine.start()
    }

    func schedule(_ buffer: AVAudioPCMBuffer, completion: (@Sendable () -> Void)? = nil) {
        player.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { _ in
            completion?()
        }
    }

    func beginPlayback() throws {
        guard !player.isPlaying else { return }
        if #available(iOS 27.0, *) {
            try player.playAudio(at: nil)
        } else {
            player.play()
        }
    }

    func setVolume(_ value: Float) {
        player.volume = min(1, max(0, value))
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// As in Autohop, keep the graph connected and update parameters in place.
    func setLevel(_ level: VocalBoostLevel, deepBass: Bool = false) throws { try configure(level, deepBass: deepBass) }

    private func configure(_ level: VocalBoostLevel, deepBass: Bool) throws {
        let stages: [(AVAudioUnitEffect, OSType)] = deepBass
            ? [(limiter, kAudioUnitSubType_PeakLimiter), (lowShelf, kAudioUnitSubType_LowShelfFilter),
               (highPass, kAudioUnitSubType_HighPassFilter), (dynamics, kAudioUnitSubType_DynamicsProcessor)]
            : [(lowShelf, kAudioUnitSubType_LowShelfFilter), (highPass, kAudioUnitSubType_HighPassFilter),
               (dynamics, kAudioUnitSubType_DynamicsProcessor), (limiter, kAudioUnitSubType_PeakLimiter)]
        for (unit, subtype) in stages {
            let parameters = VocalBoostConfiguration.parameters(for: subtype, level: level, deepBass: deepBass)
            unit.bypass = parameters.isEmpty
            for (parameter, value) in parameters {
                let status: OSStatus
                if #available(iOS 27.0, *) {
                    status = unit.withAudioUnit {
                        AudioUnitSetParameter($0, parameter, kAudioUnitScope_Global, 0, value, 0)
                    }
                } else {
                    status = AudioUnitSetParameter(unit.audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
                }
                guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            }
        }
    }

    private static func makeAudioUnit(subType: OSType) -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }
}

/// Shared by the direct-stream graph and the HLS tap. Adapted from Autohop's
/// configureVocalBoostChain; keep the processing identical across transports.
enum VocalBoostConfiguration {
    static let subtypes: [OSType] = [kAudioUnitSubType_LowShelfFilter, kAudioUnitSubType_HighPassFilter,
                                    kAudioUnitSubType_DynamicsProcessor,
                                    kAudioUnitSubType_PeakLimiter]

    static func parameters(for subtype: OSType, level: VocalBoostLevel, deepBass: Bool = false) -> [(AudioUnitParameterID, Float)] {
        if deepBass {
            // A broad bass shelf adds weight to kick drums and bass guitar.
            // Matched attenuation before the limiter reserves the shelf's full
            // headroom; no speech high-pass or dynamic compression is applied.
            switch subtype {
            case kAudioUnitSubType_LowShelfFilter:
                return [(kAULowShelfParam_CutoffFrequency, 110), (kAULowShelfParam_Gain, 5)]
            case kAudioUnitSubType_PeakLimiter:
                return [(kLimiterParam_AttackTime, 0.002), (kLimiterParam_DecayTime, 0.05),
                        (kLimiterParam_PreGain, -5)]
            default: return []
            }
        }
        guard level != .off else { return [] }
        switch subtype {
        case kAudioUnitSubType_HighPassFilter:
            return [(kHipassParam_CutoffFrequency, 180), (kHipassParam_Resonance, 0)]
        case kAudioUnitSubType_DynamicsProcessor:
            guard level != .light else { return [] }
            return [(kDynamicsProcessorParam_Threshold, -41), (kDynamicsProcessorParam_HeadRoom, 40),
                    (kDynamicsProcessorParam_ExpansionRatio, 1), (kDynamicsProcessorParam_ExpansionThreshold, -100),
                    (kDynamicsProcessorParam_AttackTime, 0.05), (kDynamicsProcessorParam_ReleaseTime, 0.2),
                    (kDynamicsProcessorParam_OverallGain, 0)]
        case kAudioUnitSubType_PeakLimiter:
            return [(kLimiterParam_AttackTime, 0.002), (kLimiterParam_DecayTime, 0.005),
                    (kLimiterParam_PreGain, level == .light ? 4 : level == .standard ? 8 : 11)]
        default:
            return []
        }
    }
}

enum VocalBoostState: Equatable, Sendable {
    case off, suspendedForSync, ready, preparing, active
    case unavailable(String)

    var isActive: Bool { self == .active }
    var message: String { message(for: "Vocal Boost") }

    func message(for effect: String) -> String {
        switch self {
        case .off: return "Off · Original broadcast audio."
        case .suspendedForSync: return "Unavailable while TV Sync is on."
        case .ready: return "Ready · Press Play to use \(effect)."
        case .preparing: return "Waiting for processed audio…"
        case .active: return effect == "Deep Bass" ? "Active · Bass enhancement is running." : "Active · Speech processing is running."
        case .unavailable(let reason): return "Unavailable · " + reason + " Playback continues without \(effect)."
        }
    }

    static func unsupportedReason(format: String?, supportsHLSTap: Bool, effect: String = "Vocal Boost") -> String? {
        guard let format else { return "Choose a station first." }
        if ["mp3", "aac"].contains(format) { return nil }
        if format == "hls" {
            return supportsHLSTap ? nil : "HLS \(effect) requires iOS 27 or later. Try a direct MP3 or AAC stream."
        }
        return "This stream format does not support \(effect). Try a direct MP3 or AAC stream."
    }
}
