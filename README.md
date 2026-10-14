# Wireless

**A native Swift and SwiftUI live radio player focused on Australian radio, for iPhone, iPad and compatible Apple-silicon Macs.**

*Fine Tuning Your Radio Presets.*

Wireless brings station discovery, favourites and live listening together in an Apple-native interface. Browse Australian metropolitan, regional, community and specialist radio, choose an available stream and listen directly from the broadcaster. The directory also includes selected New Zealand services.

## Features

- **Discover Australian radio:** browse by location, state, territory or network, or search for a station.
- **Make it yours:** save and reorder favourites, with quick access from the player.
- **TV Sync:** delay supported radio streams to help align commentary with television pictures.
- **Listening controls:** alternative streams, Vocal Boost, Sleep Timer and optional Auto Resume.
- **Apple integration:** background audio, Lock Screen and Control Centre controls, and system audio-route selection including AirPlay.
- **Cached directory:** browse the last downloaded catalogue when the directory service is unavailable. Live audio still requires an internet connection.

Stream availability, regional restrictions, metadata and TV Sync support vary by broadcaster and format. Wireless does not host or rebroadcast station audio. For detailed behaviour and troubleshooting, see the [Support Guide](SUPPORT_GUIDE.md).

## Build and run

1. Use a Mac with **Xcode 27 or later** and the iOS SDK. The app's minimum deployment target is **iOS/iPadOS 26.0**; newer APIs are guarded where required.
2. Clone this repository and open `Wireless.xcodeproj`.
3. Select the **Wireless** scheme and an iPhone or iPad simulator, then run.
4. For a physical device, select your own development team and a unique bundle identifier in Signing & Capabilities. Maintainer signing credentials are not supplied.

Compatible Mac use runs the same iOS app through Apple's Designed for iPad support. Mac Catalyst is disabled. Device compatibility and distribution depend on Apple's platform requirements.

`project.yml` is the project configuration source. If you change it, regenerate the checked-in project with `xcodegen generate`. See [development and testing](MOBILE_TESTING.md) for commands and validation boundaries.

## Repository guide

| Path | Contents |
| --- | --- |
| `Wireless/` | SwiftUI app, playback engines, audio controls and in-app support |
| `Shared/` | Station catalogue models, caching and favourites |
| `WirelessTests/`, `WirelessUITests/` | Unit and interface tests |
| `station-directory/` | Optional Cloudflare Worker catalogue service and protected editor |
| [DESIGN.md](DESIGN.md), [PAGES.md](PAGES.md) | Interface and navigation contracts |
| [SUPPORT_GUIDE.md](SUPPORT_GUIDE.md) | User-facing support source |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution and issue-reporting guidance |
| [SECURITY.md](SECURITY.md) | Private vulnerability reporting |
| [Public-content policy](Docs/PUBLIC_CONTENT_POLICY.md) | What belongs in the public repository |

The app uses the configured public catalogue API; you do not need production editor credentials or a database export to build it. The [directory service guide](station-directory/README.md) explains local service development. Production account configuration, database backups and internal research are kept separately.

## Contributing

Bug reports, accessibility improvements, station corrections and focused pull requests are welcome. Include the device, OS, app version and steps to reproduce. For playback problems, include the station and stream format, but remove personal information and credentials from diagnostic logs. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence and acknowledgements

Wireless's original code and documentation are available under the [MIT licence](LICENSE). `Wireless/VocalBoost.swift` retains the [Mozilla Public License 2.0](LICENSE-MPL-2.0.md), with derivation details in [NOTICE](NOTICE).

Broadcaster names, logos, programme information, stream content and third-party datasets remain subject to their owners' rights and applicable terms. Their presence does not imply endorsement or a grant of rights under Wireless's code licence. See [THIRD_PARTY.md](THIRD_PARTY.md).
