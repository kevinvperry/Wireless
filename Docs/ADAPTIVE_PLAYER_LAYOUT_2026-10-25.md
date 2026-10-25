# Wireless player layout — 25 October 2026

Adapted the approved Autohop player foundation from `Views/AdaptiveLayout.swift` into `Wireless/WirelessLayoutMetrics.swift`.

- The actual Playing pane viewport drives sizing, rather than the outer navigation container.
- Artwork has its own portrait size budget; longer controls increase scrollable content instead of shrinking artwork.
- A single SwiftUI Layout preserves the media and controls as a window changes between stacked and side-by-side presentation.
- Landscape containers at least 600 points wide use columns. Content is capped at 1,100 points and portrait artwork at 620 points.
- Audio output stays inline when the control area is at least 304 points wide, with a separate output row below that width. Route names truncate on one line.
- Favourite station titles truncate on one line. A flexible spacer places the shortcut tiles near the bottom of available portrait space; the bottom padding is eight points.
- Control spacing is 12 points, preserving artwork size while keeping favourite tile corners inside the phone viewport.
- Support guide and in-app Support describe the layout.

The DEBUG-only populated player fixture uses an isolated defaults suite, two long favourite names and a long simulated AirPods label. Placeholder station artwork is deliberate. It does not prove a real AirPlay connection. Radio playback, metadata and TV Sync implementations are unchanged by this work.

## Validation

- A standalone Swift check exercised 45 width/height combinations: widths 240–1,440 points and heights 320–1,366 points. It checked non-negative geometry, content containment, column separation and artwork-size invariance when controls grow from 350 to 800 points.
- Populated player UI checks cover iPhone 14 Pro Max and iPad Pro 13-inch on the iOS 27.0 simulator. The iPad check rotates between portrait and landscape. Assertions cover inline output alignment, compact favourite tiles and their visibility within the screen.
- An initial iPad failure exposed a mismatch between the artwork frame cap and its allocated height. The geometry cap was corrected and the check passed on rerun.

- Regression suite: 65 unit tests passed; one optional live-directory test was skipped because its opt-in environment flag was not enabled.
- The compatible Mac Release build passed.
- Reviewed phone and iPad portrait renders, plus a simulator display capture of the settled iPad landscape layout. XCTest landscape attachments carried incorrect rotation metadata, so the direct display capture was used for visual review.
- Screenshots and validation logs: `/Users/kevinperry/Documents/Codex/2026-10-25/wireless-layout-validation/`.

Exact iOS 27.0.1, physical iPhone/AirPods playback and interactive Mac window resizing remain unverified. No device installation, archive or App Store upload was requested.
