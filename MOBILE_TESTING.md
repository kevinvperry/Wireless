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
