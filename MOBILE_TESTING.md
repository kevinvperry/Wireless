# Wireless development and testing

Wireless is a native Swift 6 and SwiftUI iOS app for iPhone, iPad and compatible Apple-silicon Macs. Use the **Wireless** scheme. The minimum iOS deployment target is **26.0**; the current source uses APIs available in the Xcode 27 SDK.

## Local build

Open `Wireless.xcodeproj` in Xcode 27 or later. Choose an installed iPhone or iPad simulator. Physical-device builds require your own development team and bundle identifier; configure those locally before signing.

`project.yml` is the configuration source. Regenerate after changing targets or membership:

```sh
xcodegen generate
xcodebuild -project Wireless.xcodeproj -scheme Wireless \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

To run tests, first list available destinations and use an installed simulator's identifier:

```sh
xcodebuild -project Wireless.xcodeproj -scheme Wireless -showdestinations
xcodebuild -project Wireless.xcodeproj -scheme Wireless \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' test
```

`WirelessTests` covers delay correction and station-library behaviour. `WirelessUITests` covers player navigation, settings, favourites and directory interactions. The live directory unit test is opt-in: set `WIRELESS_LIVE_DIRECTORY_TESTS=1` in the scheme's test environment. UI playback tests access live services and depend on network and station availability. Tests requiring particular stations can fail when the catalogue changes.

## Manual checks

- First launch opens Discover when no station is saved. Later launches restore the selected station; audio resumes automatically only when Auto Resume is enabled.
- Search and browse stations, select alternatives, save/remove/reorder favourites and relaunch to verify persistence.
- Check Playing, Details and Sync navigation, the mini-player, Settings and Support on iPhone and iPad.
- Exercise TV Sync on supported MP3, AAC and HLS streams. Change delay and toggle Sync during playback and while paused.
- Check Vocal Boost and Sleep Timer, including cancellation and expiry.
- Verify Dynamic Type, VoiceOver, iPad rotation/multitasking and resizable compatible Mac windows.

## Physical-device validation

A successful build proves compilation. Simulator state tests do not prove audible quality or device behaviour. Separately test background playback, Lock Screen and Control Centre controls, calls, headphones, AirPlay, poor reception and reconnection. Pause during recovery and ensure connectivity returning does not override that intent.

Measured stream delay excludes downstream output latency. Supported HLS history and segment timing vary by stream. Background execution remains under operating-system control; indefinite recovery after termination or force-quit is not guaranteed.

Compatible Mac use is through Designed for iPad; Mac Catalyst is disabled. Test that destination separately from an iPad simulator.

## Supporting service

See [station-directory/README.md](station-directory/README.md) for local Worker checks. Production credentials and private research datasets are not required for the app build or the service's synthetic integration tests.

Keep [SUPPORT_GUIDE.md](SUPPORT_GUIDE.md) and `Wireless/SupportContent.swift` aligned whenever user-visible behaviour changes. Internal upload records, device identifiers and raw diagnostics belong outside the public repository.

## Early buffering and reception recovery

- With Auto Resume off, restore a previously selected station and leave the player open for a few seconds. Confirm it remains silent and shows Play; press Play and confirm playback starts. Repeat with normal playback, Vocal Boost on a direct MP3/AAC stream, and TV Sync with a saved delay.
- Leave the player idle for more than a minute, then press Play. Confirm it reconnects normally. Put the idle app in the background and confirm it does not keep preparing indefinitely.
- During playback on a physical iPhone, interrupt mobile data for at least two minutes. Confirm Reconnecting remains active across repeated cycles, including for a station with only one stream. Restore data and confirm playback resumes without pressing Play.
- Repeat the outage with the screen locked, across Wi-Fi/mobile-data transitions, with Vocal Boost, and with TV Sync. iOS may suspend recovery during a prolonged silent background outage; reopening the app must restart recovery when playback is still requested.
- During a retry wait, press Pause. Restore reception and wait at least 30 seconds; confirm playback remains paused. Repeat with a station change and confirm the previous station cannot resume.
- Compare Stream Diagnostics timestamps for `player.play`, `stream.prepared`, `stream.retryScheduled` and `playback.state`. Record startup time and recovery time separately; a simulator or successful build does not establish performance under real mobile reception.

## Stats period controls — 25 October 2026

- Adapted Autohop's glass period capsules and compact solid This/Last capsule directly, including typography, padding, colours and animation duration.
- UI checks passed on iPhone 17e, iPhone 17 Pro Max and iPad Pro 11-inch (iOS 26.5). Assertions cover horizontal centring, a shared tab baseline, selected states, previous month/year labels, This/Last selection and retaining Last through Lifetime. The iPad check also verifies landscape centring.
- Inspected simulator screenshots for the glass tabs and centred This/Last control. Results are retained in `tmp/stats-tabs/Phone26.xcresult`, `tmp/stats-tabs/SmallPhoneSigned.xcresult` and `tmp/stats-tabs/iPadSigned.xcresult`.
- The debug-only `WIRELESS_STATS_PREVIEW=1` fixture opens the real Stats view with isolated temporary listening data. It does not change the user's listening history.
- Build-for-testing passed. Initial iOS 27 and concurrent fresh-simulator runs stalled during test-runner launch; the successful checks above used individual iOS 26.5 destinations. Physical-device and accessibility text-size overflow checks were not performed.


## 25 October 2026 — approved Autohop player layout adapted to Wireless

The populated player fixture covers a long audio-output label and two long favourite names. iPhone 14 Pro Max portrait and iPad Pro 13-inch portrait/landscape UI checks run on iOS 27.0. The regression suite passed 65 unit tests with one optional live-directory test skipped. Forty-five geometry combinations cover narrow phone/window widths through large displays, including taller controls without artwork shrinkage. See `Docs/ADAPTIVE_PLAYER_LAYOUT_2026-10-25.md` for scope and limitations. Exact iOS 27.0.1, physical audio routing and interactive Mac resizing remain unverified.

## HLS Vocal Boost — 25 October 2026

Implementation and current evidence: `Docs/HLS_VOCAL_BOOST_2026-10-25.md`.

- Automated signal tests pass for rumble reduction, compression at matched loudness, peak limiting, PCM format conversion and failed-processing bypass. iOS 26.5/iOS 27 iPhone and iOS 27 iPad availability checks pass.
- Live packed-AAC HLS reaches confirmed Active through the enhanced-engine fallback on the iOS 27 iPhone simulator. The native HLS tap did not receive callbacks there; it remains unverified on hardware.
- On hardware, compare Off/Light/Standard/Strong at matched perceived loudness on speech, music and already heavily compressed broadcasts. Listen for distortion, pumping, lost consonants and excessive bass loss. Check a direct MP3, direct AAC, packed-AAC HLS and another HLS container.
- Confirm the status follows actual processing, Off returns to original playback, TV Sync suspends the effect, and automatic stream changes/reconnection do not leave a stale Active label. Check level changes during active playback, Pause/Play and station changes.
- Check locked-screen/background playback, interruptions, Bluetooth, AirPlay and compatible Mac use. A source/route that cannot supply processable audio must explain that the effect is unavailable while ordinary playback continues. FairPlay audio must remain unprocessed.

## Deep Bass — 25 October 2026

Implementation and evidence: `Docs/DEEP_BASS_2026-10-25.md`.

- In Audio Controls → Music, enable Deep Bass. Confirm Vocal Boost becomes Off; selecting a speech level must disable Deep Bass. Restart and change stations to check the saved choice.
- Check Ready/Waiting/Active/Unavailable, iOS 26 HLS unavailability, TV Sync suspension/resumption, and switching Off during playback. Listening Stats/History should count confirmed bass processing as Deep Bass, rather than Vocal Boost.
- Compare Off and Deep Bass at matched perceived loudness on rock and other music stations. Check kick/bass weight, transient detail, distortion and unwanted pumping on already compressed broadcasts. Account for the preset's reserved headroom; equal system-volume settings are not a loudness-matched comparison.
- Repeat on speakers/headphones, Bluetooth and AirPlay, with locked-screen/background playback, interruptions and compatible Mac windows. Test direct MP3/AAC and different HLS containers. Native HLS tap behaviour remains a separate hardware validation requirement.
