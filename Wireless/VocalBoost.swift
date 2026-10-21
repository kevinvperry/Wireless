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

    private let highPass: AVAudioUnitEffect
    private let dynamics: AVAudioUnitEffect
    private let limiter: AVAudioUnitEffect

    init(format: AVAudioFormat, level: VocalBoostLevel) throws {
        highPass = Self.makeAudioUnit(subType: kAudioUnitSubType_HighPassFilter)
        dynamics = Self.makeAudioUnit(subType: kAudioUnitSubType_DynamicsProcessor)
        limiter = Self.makeAudioUnit(subType: kAudioUnitSubType_PeakLimiter)

        engine.attach(player)
        engine.attach(highPass)
        engine.attach(dynamics)
        engine.attach(limiter)
        if #available(iOS 27.0, *) {
            try engine.connectNode(player, to: highPass, format: format)
            try engine.connectNode(highPass, to: dynamics, format: format)
            try engine.connectNode(dynamics, to: limiter, format: format)
            try engine.connectNode(limiter, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(player, to: highPass, format: format)
            engine.connect(highPass, to: dynamics, format: format)
            engine.connect(dynamics, to: limiter, format: format)
            engine.connect(limiter, to: engine.mainMixerNode, format: format)
        }
        configure(level)
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

    private func configure(_ level: VocalBoostLevel) {
        switch level {
        case .off:
            highPass.bypass = true
            dynamics.bypass = true
            limiter.bypass = true
        case .light:
            configureHighPass()
            highPass.bypass = false
            dynamics.bypass = true
            configureLimiter(preGain: 4)
            limiter.bypass = false
        case .standard:
            configureHighPass()
            highPass.bypass = false
            configureDynamics()
            dynamics.bypass = false
            configureLimiter(preGain: 8)
            limiter.bypass = false
        case .strong:
            configureHighPass()
            highPass.bypass = false
            configureDynamics()
            dynamics.bypass = false
            configureLimiter(preGain: 11)
            limiter.bypass = false
        }
    }

    private func configureHighPass() {
        set(highPass, kHipassParam_CutoffFrequency, 180)
        set(highPass, kHipassParam_Resonance, 0)
    }

    private func configureDynamics() {
        set(dynamics, kDynamicsProcessorParam_Threshold, -41)
        set(dynamics, kDynamicsProcessorParam_HeadRoom, 40)
        set(dynamics, kDynamicsProcessorParam_ExpansionRatio, 1)
        set(dynamics, kDynamicsProcessorParam_ExpansionThreshold, -100)
        set(dynamics, kDynamicsProcessorParam_AttackTime, 0.05)
        set(dynamics, kDynamicsProcessorParam_ReleaseTime, 0.2)
        set(dynamics, kDynamicsProcessorParam_OverallGain, 0)
    }

    private func configureLimiter(preGain: Float) {
        set(limiter, kLimiterParam_AttackTime, 0.002)
        set(limiter, kLimiterParam_DecayTime, 0.005)
        set(limiter, kLimiterParam_PreGain, preGain)
    }

    private func set(_ unit: AVAudioUnitEffect, _ parameter: AudioUnitParameterID, _ value: Float) {
        if #available(iOS 27.0, *) {
            _ = unit.withAudioUnit { audioUnit in
                AudioUnitSetParameter(audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
            }
        } else {
            AudioUnitSetParameter(unit.audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
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
