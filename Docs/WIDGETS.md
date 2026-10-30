# Home & Lock Screen widgets

Wireless adapts Autohop's widget architecture: an atomic, display-only App Group snapshot; prepared station artwork; a timeline provider; and an `AudioPlaybackIntent` declared in both targets with playback implemented only in the containing app. The widget never receives stream URLs, request headers or the full catalogue.

Apple documents app-process execution for this intent in [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

## Design

Home Screen widgets copy Autohop's layered charcoal background, subtle texture, native container glass sheen, purple status headings, white titles and explicit white metadata at 64% opacity. Playback buttons use Autohop's purple gradient, highlight, border and shadow; native glass is kept off interactive labels because Autohop's on-device checks found those labels could disappear in WidgetKit.

Selected-station artwork scales with the available widget height. The large layout distributes its favourite rows through the remaining height instead of leaving a trailing spacer. Lock Screen controls retain the system's monochrome presentation.

## Presentation and behaviour

- Small: selected station, artwork and play/pause.
- Medium: selected station and the first two other favourites.
- Large: selected station and the first four other favourites.
- Extra-large: selected station and up to six other favourites in two columns.
- Lock Screen circular and rectangular: selected-station play/pause.
- Lock Screen inline: selected-station text; tapping opens Wireless.

Favourites follow the user's manual order. The primary station is excluded from the remaining favourites. If no station is selected, the first favourite is primary. An empty library prompts the user to open Wireless. Play switches to the identified station or resumes it; pause affects only that station if it is still current. Explicit play/pause requests are idempotent, so a stale pause request cannot accidentally start playback or pause another station.

Station identity is resolved in the app against current catalogue, saved favourites or the selected station. The existing MobilePlayer owns audio, stream selection, output, sleep behaviour and TV Sync's station-change reset. Controls indicate pause while playback is requested, including connection/buffering, so a pending stream can be stopped.

Snapshots update after station, playback-request or favourites changes; progress ticks do not trigger widget reloads. Artwork is flattened onto white and cached by station identity plus logo URL. Failed artwork uses a radio placeholder. Old thumbnails are removed after publication completes. Shared files use protection available after the first device unlock.

## Project and signing

`project.yml` embeds `WirelessWidgets` and declares `group.au.com.kevmarl.Wireless` for both app and extension. Both targets support iPhone and iPad, including compatible Designed for iPad Mac installations. Keep extension and app versions aligned when changing the release version.

A signed device build must provision the new widget bundle ID and App Group for team QT3N6256FG. Simulator builds with code signing disabled do not verify those Apple Developer resources.

## Validation

- Simulator app and embedded extension build passed.
- Full unit suite passed: 87 tests, one skipped, zero failures.
- Targeted snapshot/storage and layout checks passed: four tests, zero failures.
- Rendered layouts cover ten variants: small in light and dark modes, medium and large at compact phone and iPad sizes, a larger phone layout, extra-large, circular and rectangular families, using long names and six favourites. These are SwiftUI renders at representative widget dimensions, not WidgetKit-host screenshots.
- Physical locked-screen playback, background launch, real widget refresh timing, signed provisioning and compatible Mac widget-host behaviour remain unverified.

Before release, add each supported family from the real widget gallery, check logo appearance in full-colour and tinted modes, reorder favourites, switch and pause stations, and test from a locked device after the app has been backgrounded. Confirm that cold-launch controls and unavailable-network recovery use the same player as Wireless and CarPlay.
