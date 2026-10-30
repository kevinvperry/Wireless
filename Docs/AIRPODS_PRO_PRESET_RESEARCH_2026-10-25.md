# AirPods Pro music preset research — 25 October 2026

Research and design proposal only. No preset, playback behaviour or Apple device setting has been changed. Sources were checked against current Apple documentation and Wireless's current playback code.

## Recommendation

Prototype a gentle, optional “AirPods Balance” music preset, initially as an alternative to the other music presets. Aim for bass definition, natural vocals and comfortable treble at a comparable listening level. Treat the tuning as a preference established through listening, rather than a universal correction for all AirPods Pro.

Confirm the AirPods Pro generation before settling a profile. Test Pro 2 and Pro 3 separately if both are supported; include Pro 1 separately before claiming support. No acoustic measurements or physical listening comparisons were performed in this research.

## What Apple already provides

Apple describes Adaptive EQ as adjusting sound to the fit of AirPods Pro 2 and Pro 3 in real time. A good ear-tip seal also affects bass and noise cancellation. This makes an aggressive fixed “inverse headphone response” a poor starting assumption. That last conclusion is a design inference, not a measured correction curve. Sources: [Apple hearing features](https://www.apple.com/airpods-pro/hearing-health/) and [Apple ear-tip guidance](https://support.apple.com/en-au/119849).

The iOS 27 AirPods guide documents a separate three-band Custom EQ, with Low/Mid/High controls under Settings > AirPods > Audio & Routing > Equaliser. Apple lists Pro 2 and later among supported models. These settings are stored on the AirPods and carry to other paired devices. This is separate from a Wireless preset, which would process only Wireless's stream. Sources: [Custom EQ guide](https://support.apple.com/guide/airpods/customize-eq-te819024i19r/27/web/27) and [supported headphones](https://support.apple.com/en-au/102663).

Other variables matter during comparison: Headphone Accommodations can adjust media sound; Personalised Volume changes media level based on surroundings/preferences; Conversation Awareness can lower media when the wearer speaks; Spatial Audio/head tracking has per-app settings. Record those settings so their effects are not mistaken for Wireless DSP. Preserve the listener's hearing-assistance configuration. Sources: [Headphone Accommodations](https://support.apple.com/en-au/102663), [Adaptive Audio features](https://support.apple.com/en-gb/104979) and [Spatial Audio controls](https://support.apple.com/en-au/guide/airpods/dev00eb7e0a3/27/web/27).

## How a Wireless preset could work

The current shared processor in `Wireless/VocalBoost.swift` supplies the direct MP3/AAC engine and native HLS tap. It already has low-shelf, parametric presence, high-shelf and peak-limiter stages. Its speech high-pass and dynamics stages are bypassed for music. Autohop's PlaybackEngine and route-change handling were inspected; no ready-made AirPods correction profile was identified there.

Use the same connected graph and in-place parameter updates. Retain the HLS lifecycle lock, bounded source pulls and original-signal bypass. Keep the playback audio session in its existing default playback mode, with no microphone activation or session-mode changes to enable a music preset. HLS would retain Wireless's present processing availability limits, including native processing on iOS 27 and compatible unencrypted AAC fallback.

The first experiment should be near neutral, testing small broad changes rather than narrow treble notches:

| Area | Prototype range to audition | Intended effect |
| --- | --- | --- |
| Bass, roughly 60–90 Hz | 0 to +1.5 dB | A little weight without the existing Deep Bass lift |
| Low mids, roughly 200–350 Hz | 0 to −1 dB | Test whether a broad reduction improves separation |
| Vocal presence, roughly 2–3 kHz | 0 to +0.75 dB | Small clarity change without speech compression |
| Treble | Flat initially | Avoid adding brightness before hearing the actual model |
| Dynamics | No extra programme compressor; peak protection | Preserve the dynamics available in the broadcast |

These are proposed listening-test ranges, not measured AirPods compensation values or an implementation specification. A low-mid cut alongside a separate vocal lift would require a second parametric stage; the current graph has only one. Connect any additional stage once and bypass it for other presets. Do not rebuild the graph on each selection.

Avoid the earlier fixed 5 dB whole-programme reduction. Measure peak behaviour and use only the gain management needed for the chosen curve. Do not promise identical perceived loudness or true-peak protection merely because the current sample-peak tests pass. Equalisation cannot restore information or dynamics removed upstream.

## Routing and user control

Apple's documented audio-route interface exposes port type, descriptive name, UID and other capabilities. Neither that reviewed interface nor the inspected SDK header provides a documented AirPods Pro generation identifier or an interface for reading/writing Adaptive EQ, Custom EQ or the listener's hearing profile. This is a finding about the inspected playback API, not proof about every Apple framework. Source: [AVAudioSessionPortDescription](https://developer.apple.com/documentation/avfaudio/avaudiosessionportdescription?changes=_8).

Wireless currently displays the first output's name and groups Bluetooth routes for statistics. It does not identify AirPods generations. Do not treat a name containing “AirPods” as reliable model identification. A first version should let the listener select their model/profile manually. An optional “remember for this output” preference could use the reported route UID with manual fallback when identity changes; do not promise a permanent Bluetooth identity.

Proposed behaviour: explicitly opt in; suspend the headphone profile on speakers, CarPlay or AirPlay; preserve deliberate Pause after disconnect; restore only the opted-in profile on a recognised output. If route scoping becomes automatic, keep stored user preference separate from the currently effective DSP state. For the first version, make this preset mutually exclusive with Mid Bass, Deep Bass, Pop & R&B and Vocal Boost. A later independent headphone-tuning layer would need combined-curve and gain testing before it could safely coexist with genre presets.

## Listening and technical acceptance plan

1. Confirm generation, firmware, ear-tip fit and iOS. Record Apple's EQ, listening mode, Personalised Volume, Conversation Awareness, Spatial Audio and relevant media accommodations. Keep the settings constant during each A/B comparison. Where suitable for the listener, use Recommended EQ and standard stereo for the initial baseline; retain their usual accessibility configuration.
2. Compare Wireless Off, existing Pop & R&B and the new prototype using the same repeatable audio excerpts and matched loudness. A louder preset must not win by level alone. Live songs changing during A/B are a poor controlled comparison, so use suitable licensed/local test material for development as well as live-station trials.
3. Cover bass-heavy modern pop/R&B, dense rock, acoustic vocals, cymbals/sibilants and talk/ad transitions. Repeat at comfortable low and moderate levels, then check longer listening comfort.
4. Test ANC, Adaptive and Transparency separately, then Spatial Audio if the listener uses it. Include both Pro 2 and Pro 3 before using one generic public claim.
5. Verify response, impulse/transient behaviour, channel consistency, sample and oversampled peaks, bypass accuracy and smooth changes. Check compressed near-full-scale material for limiter pumping and distortion.
6. Run direct AAC/MP3 and native HLS, repeated preset changes, Pause cleanup, reconnects, output changes, one-ear use, interruptions, background and locked-screen playback. Do not introduce audible mode-change jumps or accidental speaker playback.

Proceed to a limited listening prototype first. Final naming, coefficients and any model-specific variants should follow the comparison results. Update Support only when behaviour is implemented.
