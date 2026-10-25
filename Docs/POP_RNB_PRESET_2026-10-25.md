# Pop & R&B music preset — 25 October 2026

## Purpose and naming

The name states its intended use beside Mid Bass and Deep Bass. It is a distinct music voicing aimed at modern pop, R&B and electronic beats, rather than a stronger version of the guitar-oriented bass presets. It cannot restore dynamics removed by the source or provide universally ideal tuning across speakers and headphones.

## Processing

- Low shelf: +3 dB at 75 Hz for deeper beat weight (rock presets remain +2.5/+5 dB at 110 Hz).
- Broad presence EQ: +1 dB at 2.5 kHz, Q 0.7, for a small vocal lift.
- High shelf: +1.5 dB at 10 kHz for a restrained treble lift.
- Peak limiter: unity pre-gain, 2 ms attack, 50 ms decay. No speech high-pass or speech compressor.

Inspected Autohop's PlaybackEngine and PlaybackControlsCard; neither had an equivalent pop/R&B preset. Wireless extends the shared Audio Unit configuration using the parameter identifiers and supported ranges in Xcode's AudioToolbox SDK headers. AVAudioEngine and native HLS use the same tables. Presence and high-shelf stages are connected once, then bypassed outside Pop & R&B; switching keeps the existing graph and stream connection. The HLS lifecycle lock and bounded source-pull behaviour remain in place.

## Settings and presentation

MusicPreset replaces the binary/bass-specific model. Existing `bassBoostLevel` and original `deepBassEnabled` values remain migration inputs; new choices persist as `musicPresetLevel`. Music and Vocal Boost remain mutually exclusive, with temporary suspension for TV Sync. Listening statistics have a distinct Pop & R&B mode without changing existing stored mode identifiers.

Four labelled choices with descriptions and selection marks replace the narrow segmented music picker. This accommodates the names and larger text within the existing TV Sync card style. The in-app and project Support guides describe each preset and suggest comparing familiar music with Off.

## Validation

- Unit suite: 84 executed, 83 passed and one optional live-directory test skipped. Tests verify the distinct response at 40 Hz, 2.5 kHz and 16 kHz at both 44.1/48 kHz, near-full-scale limiting in mono/stereo and interleaved/planar PCM, and repeated in-place switching back to exact original-signal bypass.
- iPhone and iPad simulator layout checks passed; iPad portrait/landscape screenshots were inspected. Largest accessibility-text layout passed.
- Physical iPhone, iOS 27.0.1, Rock ’n’ Road Trip HLS: three cycles of all music choices and speech levels passed. Pop & R&B was confirmed selected and Active in each cycle. Playback remained Playing; final speech processing and app survival after Pause also passed. This stream tests native HLS processing and switching, not subjective pop/R&B suitability.
- Saved-setting check passed for Pop & R&B persistence across relaunch, speech/music exclusivity and suspension for TV Sync. The test waits for the Sync pane to be fully visible before toggling its switch.
- Final signed physical-device build succeeded and was installed on the connected iPhone. No archive or App Store upload was performed.

Subjective listening quality, Bluetooth/AirPlay, prolonged background playback and compatible Mac audio require separate checks. Live-stream switching checks establish stability and processing activity, not ideal genre tuning.
