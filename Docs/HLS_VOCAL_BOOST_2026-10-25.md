# HLS Vocal Boost — 25 October 2026

## Backup

Before implementation, the existing tracked changes and new source, tests and project documentation were committed as `17b565b620cff6b223b11226d5ae3eafe44d425c` and pushed to GitHub `main`. `git ls-remote origin refs/heads/main` confirmed the exact commit. Existing exclusions for credentials, private research/operational records and generated or temporary files were respected; those local files were not published to the public repository.

## Behaviour

- Direct MP3/AAC retains the Autohop-derived high-pass → dynamics → limiter graph. Both playback paths share its parameter definitions and check configuration errors. Light bypasses dynamics; Standard and Strong apply compression with different limiter gain.
- iOS 27 HLS first uses Apple's mixed-output audio processing tap on AVPlayer. The tap converts actual PCM formats into the effects' float format, applies the same chain, absorbs reported processing latency, and converts back. Render buffers are allocated during preparation. Failures preserve the original source audio.
- If native processing does not deliver audio after ten seconds of advancing playback, Wireless tries an unencrypted ADTS AAC-segment fallback adapted from the existing RadioStreamEngine downloader. It follows a bounded master-playlist chain, strips ID3 metadata, preserves request headers and validates segment data. Encryption, fragmented MP4, byte ranges and other containers are rejected by this fallback. Failure returns to ordinary AVPlayer playback and explains that speech processing is unavailable. There can be a short reconnection during the switch.
- iOS 26 retains direct MP3/AAC processing. HLS displays an explicit iOS 27 requirement. TV Sync suspends Vocal Boost.
- Audio Controls distinguishes Off, Ready, Waiting, Active and Unavailable. Active requires successful processed-frame telemetry (or the enhanced engine's rendered-buffer callback), rather than a selected preference. Listening Stats uses this confirmed state.
- Changing Light/Standard/Strong while the enhanced engine is active changes the connected graph in place, as in Autohop. Off returns to ordinary AVPlayer playback.
- The in-app Support guide and SUPPORT_GUIDE.md describe support and limitations. Start with Light for broadcasts that already use heavy compression. This feature cannot recover detail absent from a low-bitrate source.

## Validation

- iPhone 18 Pro, iOS 27 simulator: 75 unit tests executed, 74 passed and the existing opt-in live-directory test skipped; availability UI passed.
- iPad Pro 13-inch, iOS 27 simulator: the same unit suite and availability UI passed. Screenshot inspected.
- iPhone 17 Pro Max, iOS 26.5 simulator: the same unit suite and explicit HLS-unavailable UI passed.
- Live SEN packed-AAC HLS, iOS 27 iPhone simulator: AVPlayer continued playback but the native tap received no prepare/process callbacks. Wireless detected this, switched to the AAC-segment fallback, and confirmed Active from rendered audio. The live UI test passed, including changing Standard to Strong while active and switching Off back to ordinary playback. This verifies the fallback, not native HLS tap execution.
- Signal tests cover 44.1/48 kHz, mono/stereo, interleaved and non-interleaved float PCM, signed 16-bit PCM conversion, rumble attenuation, finite output, peak limiting, failed-processing bypass and re-preparation. A loudness-matched comparison confirms compression improves quiet audio relative to loud audio; a uniform gain increase cannot pass that test.
- Parser tests reject protected, fragmented and byte-range playlists and non-ADTS data, and exercise sequence/relative-URL handling and ID3 stripping.
- Unsigned generic iOS device build succeeded. No archive or TestFlight upload was performed.

Physical-device listening, background playback, interruptions, Bluetooth, AirPlay, compatible Mac playback, and the native HLS tap still require validation. Synthetic signal tests do not establish subjective naturalness or rule out pumping on every broadcaster's already processed audio. Neither successful compilation nor successful AAC fallback verifies native HLS tap behaviour.

## Apple references

- [What's new in HLS, 2026](https://developer-rno.apple.com/streaming/Whats-new-HLS.pdf), “MTAudioProcessingTap for HLS”: mixed-output taps and the FairPlay exclusion.
- Installed iOS 27 SDK, AVAudioMix.h and MTAudioProcessingTap.h: availability, preferred-format requirements, real-time constraints and latency absorption.
- [Audio Converter Services](https://developer.apple.com/documentation/audiotoolbox/audio-converter-services): same-rate PCM format conversion.
