# Mid Bass and Audio Controls — 25 October 2026

## Behaviour

Audio Controls now offers Off, Mid Bass and Deep Bass. The low shelf remains at 110 Hz: Mid Bass uses +2.5 dB and Deep Bass +5 dB. Both use unity limiter pre-gain instead of the original −5 dB reduction, retaining normal midrange level while limiting boosted peaks (2 ms attack, 50 ms decay). This removes the deliberate whole-programme attenuation; perceived loudness still depends on the source and playback equipment.

The direct-stream engine and native HLS tap share the same parameter tables. All six presets (four speech states and two bass states) use the existing connected graph; switching does not rebuild the tap, reconnect the stream or change the audio session mode. Original-signal bypass, lifecycle protection and bounded latency compensation are retained.

The persisted `bassBoostLevel` has off/mid/deep values. Existing `deepBassEnabled` preferences migrate to Deep Bass when no new preference exists. Choosing Vocal Boost turns bass off and vice versa. TV Sync temporarily suspends the saved sound preset. Listening statistics distinguish active Mid Bass and Deep Bass while retaining existing Deep Bass history.

## Presentation

Inspected Autohop's PlaybackControlsCard and PlaybackEngine as the equivalent implementation. Wireless adapts the grouped controls and in-place DSP parameters, using its own TV Sync pane's 22-point padding, 20-point rounded cards, purple symbols, explanatory copy and 720-point content limit. Music, speech and stream choices have separate cards. Explanations describe what to try without DSP terminology. Accessibility text sizes use menu pickers instead of squeezing segmented labels. The page scrolls within narrow or short windows. Support source and in-app guide are updated together.

## Validation

- Unit suite: 82 executed, 81 passed and one optional live-directory test skipped. Tests measure unchanged 1 kHz level within 0.3 dB, halfway bass gain at 44.1/48 kHz, bounded peaks for near-full-scale bass, in-place changes through both bass presets, and exact Off bypass.
- iPhone simulator: redesigned cards, Deep Bass and Mid Bass persistence across restarts, speech exclusivity and TV Sync suspension passed. Largest accessibility text layout passed with menu pickers.
- iPad simulator: portrait and landscape layout checks passed; exported screenshots were inspected along with iPhone and large-text captures.
- Physical iPhone, iOS 27.0.1, Rock ’n’ Road Trip HLS: three cycles of speech levels and Mid Bass/Deep Bass/Off passed while playback remained Playing. Final Strong selection and active processing were confirmed, and Pause cleanup left the app running.
- The first device run kept playback running but failed the final preset assertion: the tap requested Strong while the observed selection remained Off. The test now requires controls to be fully inside the visible area before tapping and explicitly checks final selection; the rerun passed. No processing change was made in response to that test-selection failure.

Subjective loudness/music listening, Bluetooth/AirPlay, prolonged background playback and compatible Mac runtime behaviour remain unverified. Container-based layout and scrolling support narrow/short windows, but simulator screenshots are not Mac runtime certification. No archive or App Store upload was performed.
