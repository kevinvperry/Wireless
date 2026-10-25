# Sound mode switching reliability — 25 October 2026

## Confirmed faults and changes

Physical iPhone crash reports showed the HLS processing callback using Audio Units while AVFoundation's cleanup queue disposed them. Preparation and disposal now share a lifecycle lock; the render callback only tries that lock and passes through source audio if busy.

The native tap now keeps one prepared graph for all Vocal Boost levels, Deep Bass and Off. Atomic preset requests update parameters and bypass stages in the rendering callback. Switching Off preserves the current connection and queued audio. The playback audio session stays in its default long-form mode instead of changing session mode for each preset.

Device testing also exposed repeated StartOfStream flags during look-ahead reads. Repeatedly resetting latency compensation could consume source audio without returning output, starving AVPlayer. Compensation now resets only on the first pull of a callback, with a bounded source-frame budget.

Enhanced-engine callbacks carry playback-generation identifiers so obsolete streams cannot update current playback. Parser failure cleanup is deferred until synchronous parsing callbacks have returned. Preview playback tests use an isolated listening-stats store.

## Validation

- Unit suite: 81 executed, 80 passed; one optional live-directory test skipped.
- Three targeted processing regressions passed with Thread Sanitizer enabled: concurrent rendering/cleanup, in-place preset changes with exact Off PCM bypass, and repeated source-start flags.
- Physical iPhone on iOS 27.0.1: Rock ’n’ Road Trip and Triple M Melbourne HLS each passed three cycles of Vocal Boost levels, Off and Deep Bass toggles while remaining Playing; final processing became Active and the app remained running after Pause.
- Simulator switching checks passed for packed-AAC HLS fallback on iPhone and direct Triple M AAC on iPad.

Earlier physical iterations failed and led to the additional graph and latency fixes above. The passing result applies to the final implementation. These checks establish switching and cleanup behaviour; subjective listening quality, prolonged playback, Bluetooth, AirPlay, interruptions, locked-screen playback and compatible Mac audio remain separate checks. No archive or App Store upload was performed.
