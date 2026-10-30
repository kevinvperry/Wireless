# ShazamKit Stage 1 — Identify song

Implemented 30 October 2026. The existing App ID’s ShazamKit App Service was enabled separately in Apple Developer; no fabricated ShazamKit entitlement or MusicKit permission is required.

## Backup

Before feature edits, the current tracked source and outstanding widget source work were committed as `d3e78e9846908e023551ae8e7116bfcba5323f38` and pushed to `codex/backup-before-shazamkit-2026-10-30`. `git ls-remote` verified that exact remote commit. Private operational research, generated output, credentials and ignored build artefacts were not published.

## Behaviour

- The Playing pane has an Identify song action beside Play/Pause. It is disabled while paused, buffering or using TV Sync.
- One attempt fingerprints roughly ten seconds of audio and submits one signature to `SHSession`. A 30-second deadline covers capture and the service response.
- Results stay separate from broadcaster song/programme metadata. A result offers artwork, an Apple Music link when supplied, and explicit saving through `SHLibrary`. Missing Apple Music links fall back to a Shazam link when supplied.
- No microphone recording, automatic library writes, stored audio, recognition history or continuous recognition.
- Each attempt has its own identity. Closing/cancelling, changing the stream/station/backend, pausing, or leaving the foreground cancels sampling and rejects late callbacks. A save finishing after dismissal cannot alter the next sheet.
- Shazam failures log only error domain/code in opt-in Stream Diagnostics; fingerprints and sampled audio are not logged.

## Audio paths and limitations

1. HLS on iOS 27+: attach `AVPlayerItemSampleBufferOutput` to the current item with normal rendering retained. Pull decoded PCM at the playback clock, skip prior decoder history and hold future samples until due. Detach on completion/cancellation. Reject discontinuities rather than combining unrelated audio.
2. EnhancedLiveStreamEngine playback: reuse freshly allocated decoded PCM before sound processing. No second stream or new audio engine.
3. Other direct MP3/AAC and compatible unencrypted packed-AAC HLS: a bounded, silent connection uses the existing parser/decoder in sample-only mode. It never creates an audio engine or alters audible playback. The sheet explicitly explains extra data use and that personalised adverts/timing can differ.

The sample-only decoder stops after roughly ten seconds of decoded audio; the outer deadline also bounds failed/stalled downloads. Unsupported iOS 26 HLS containers, protected content and routes that do not expose audio fail explicitly. No claim is made that a matched recording is the main programme music rather than an advert or background bed.

Autohop was searched for SHSession/SHManagedSession/Shazam integration; none was found. The feature adapts Wireless’s existing Autohop-derived player/sheet patterns and reuses its established decoder. Both Support guide sources were updated.

## Validation

- Simulator and unsigned iOS device-target builds succeeded. A compatible Mac target build also succeeded.
- The full unit suite ran 93 tests, with one existing test skipped and zero failures. A subsequent focused run of recognition, HLS parser and Vocal Boost tests passed 24 tests, including native output detachment and duplicate-stop safety.
- A rolling live HLS fixture also passed capture through the current player, submission to Shazam, dismissal/retry and continued playback across segment boundaries. An initial finite VOD fixture was unsuitable because normal live-edge preparation left fewer than ten seconds before its end.
- A local generated AAC tone exercised playback, starting identification, dismissal, retry and pause on the simulator. Playback remained requested throughout identification and dismissal. The audio produced a signature, but the Shazam service returned an error; this does not validate successful online song recognition.
- iPhone 18 Pro Max, smaller iPhone 17e and iPad mini (iOS 27) result, no-match, error and progress layout checks passed, including the largest accessibility text setting.
- Result/error/progress layouts use isolated DEBUG fixtures. Fixtures cannot write to the real Shazam library. A synthetic SHMatchedMediaItem fixture was replaced with a plain presentation model after it proved invalid at runtime.
- One repeated playback test stalled before identification in the simulator’s pre-existing UserNotifications daemon call. The isolated preview player now disables its notification-dismissal callback; production Sleep Schedule behaviour is unchanged.

Successful recognition of real broadcast music, real SHLibrary writes, physical headphone/AirPlay playback and physical-device/Mac runtime behaviour remain unverified. No archive, TestFlight upload or App Store submission was performed.

## Repeating the optional playback check

Run `python3 Scripts/shazamkit-fixture.py` on the Mac before the optional playback tests. It uses Python’s standard library and macOS `afconvert` to generate a tone, then serves direct AAC and a rolling live packed-AAC HLS playlist with transport timestamps on `127.0.0.1:18742`. Stop with Ctrl-C; temporary files are cleaned up. Nothing is downloaded or recorded. Playback tests skip if the fixture is absent; presentation checks need no server. The synthetic tone cannot validate a real music match.

## Apple references

- https://developer.apple.com/documentation/shazamkit/shsession
- https://developer.apple.com/documentation/shazamkit/shsignaturegenerator/append(_:at:)
- https://developer.apple.com/documentation/avfoundation/avplayeritemsamplebufferoutput
- https://developer.apple.com/documentation/shazamkit/shlibrary/additems(_:)
- https://developer.apple.com/design/human-interface-guidelines/shazamkit
- https://developer.apple.com/help/account/services/shazamkit/

## Physical-device failure diagnostics

The opt-in Stream Diagnostic Log now gives every identification attempt a shared
`attemptID` across the controller, PCM capture, decoder and Shazam delegate. It
records app/OS and station/stream configuration, generic output route types,
network state and changes, audio interruptions, capture backend selection,
requested/actual PCM format, buffer/frame counts, captured duration, bounded
peak/RMS silence indicators, HLS empty/stale/future-buffer counts and player
errors. Decoder HTTP responses and parser/converter OSStatus values are included.
Fingerprint duration and byte count are recorded, followed by submission,
matching/no-match/error callbacks, late-result rejection, timeout phase and
cancellation reason. Library-save attempts have separate outcome/error events.

Apple error domains, codes, descriptions, recovery suggestions and bounded
underlying error chains are preserved. Arbitrary error userInfo, raw audio,
fingerprint bytes, request headers, URL credentials/paths/queries and personal
output-device names are excluded from Shazam events. Service enablement on the
Apple Developer App ID cannot be confirmed by this runtime log. Recording remains
opt-in, with the existing capped/rotated storage and complete export.

Enable **Record Stream Diagnostics** before reproducing on the iPhone. Select
**Shazam**, then refresh after the result and share the complete log. The selected
filter only changes the viewer; export also includes playback/network context.
This instrumentation does not establish the cause of a physical-device failure.

Diagnostic validation: the full unit suite passed 100 tests (one existing skip,
zero failures). Six new diagnostic tests cover nested/bounded Apple errors,
redaction, attempt correlation, silent PCM/format failure, timeouts and the
recording switch/export. The generated rolling-HLS UI integration passed and its
actual app log showed correlated capture, fingerprint generation, submission,
error, shutdown and retry events. Its simulator callback reported Shazam error
202 with debug description `Missing entitlements`, plus AMSErrorDomain 306.
That simulator result is not evidence of the failure on the user's iPhone;
the updated physical-device log is still needed. Unsigned device Release builds
also passed; no installation, archive or upload was performed for this change.

## HLS tap capture and bounded fallback

The physical-device log dated 30 October showed three attempts with zero PCM
buffers from AVPlayerItemSampleBufferOutput, despite continuing playback. Deep
Bass's mixed-track audio tap had processed audio. HLS recognition now prefers
that existing tap when present, avoiding a second output on the same player item.
It preserves the existing native output when no processing tap exists and the
existing enhanced decoder when that is the audible playback backend.

`TapSongSamples` hands off rendered PCM through two prepared pools of 16 buffers.
The audio callback only tries a lock and copies into existing storage. A single
consumer drains every 50 ms and creates independently owned buffers outside the
render callback and outside the pool lock. Overflow, contention and source
restarts are treated as discontinuities rather than silently stitching audio.
Capture is disabled and detached when the attempt stops; playback is retained.

A three-second period without new PCM, or an explicit capture discontinuity,
permits one fallback to the existing sample-only decoder for the selected stream.
The partial fingerprint is discarded before new-source audio is appended. The
sheet explains the extra connection and possible timing/personalised-advert
variation. A further three-second no-audio period fails promptly. The overall
30-second deadline remains. Station changes, dismissal and playback teardown
still cancel capture. Diagnostic events identify the initial source, selected
source, fallback reason, fingerprint reset and no-audio deadline.

Autohop's PlaybackEngine was inspected for equivalent bounded PCM handling. It
uses a background reader with bounded backpressure for its local-file engine;
there is no equivalent Shazam/HLS-tap consumer to copy. Wireless retains its
Autohop-derived DSP graph and adds a non-waiting hand-off for the native callback.

Validation of this repair:

- The final full unit suite passed 105 tests, with one existing skip and zero
  failures. Tests exercise the actual tap render callback through the hand-off
  and SHSignatureGenerator, independently owned copies across pool reuse,
  interleaved/non-interleaved Float32/Int16 storage, overflow/discontinuity
  rejection, the single-fallback deadline and partial-fingerprint reset.
- Generated rolling-HLS playback passed through the ordinary native output. A
  forced silent live source passed the separate-decoder fallback UI check; the
  actual app log recorded fallback at 3.2 seconds, reset, a new ten-second
  fingerprint and catalogue submission under the same attempt ID. Dismissal,
  retry and continued playback controls also passed.
- The iOS 27.0 simulator did not activate its native HLS processing tap for the
  Deep Bass fixture. The first attempt was correctly cancelled when the existing
  sound-processing fallback changed the audible backend. A subsequent test after
  that backend settled passed recognition capture through the enhanced decoder.
  This does not validate a physical HLS tap; that hand-off has deterministic
  render-callback coverage and still needs an iPhone retest.
- Simulator catalogue requests continued to report error 202, Missing
  entitlements. Successful real-music matches and physical Bluetooth audio remain
  unverified. No device installation, archive or upload was performed.
