# Autohop and Wireless: iPhone Duo compatibility review

Reviewed 25 October 2026. Preparation and source audit; no app implementation changed.

Implementation follow-up: Autohop has implemented and validated the reusable adaptive player/navigation foundation described in [its implementation report](/Users/kevinperry/Developer/Autohop/Docs/ADAPTIVE_PLAYER_NAVIGATION_2026-10-25.md). The findings below record the pre-change baseline. Wireless implementation remains unchanged in this phase.

## Assessment

Both apps have useful adaptive foundations, but neither should yet be described as Duo-optimised or Duo-tested. The principal work is player layout, navigation bars, presentation continuity and validation on the new form factor. Retain the existing playback engines and app behaviour while adapting their presentation.

A toolchain update is necessary for the complete implementation: this computer has Xcode 27.0 (27A266a), iOS SDK 27.0 and iOS 27.0 simulators. Its installed simulator device types contain no Duo. Apple documents the principal new APIs as iOS 27.1+. The installed SwiftUI and SwiftUICore interfaces contain neither ArrangementView, reservedRegions, toolbarVerticalEdge nor ToolbarContent.axisBehavior. A runtime availability check alone cannot make these symbols compile with the installed SDK.

Apple's preparation talk explicitly distinguishes building against iOS 27 from building against iOS 27.1: the latter enables the full edge-to-edge experience and vertical system bars. Use Xcode 27.1 and its corresponding SDK/device support for final Duo work. Existing minimum OS versions can remain: Autohop 17.0 and Wireless 26.0, with availability-gated new layouts and established fallbacks.

Source: [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/), [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview).

## Apple guidance mapped to these apps

Apple's overview calls for resizing between displays and poses, system navigation containers, container-relative measurements, and accommodating fold divisions and camera occlusions. Safe-area padding alone does not describe an internal fold. Custom layouts can query reserved regions; system containers already handle many cases. Vertical bars need semantic toolbar items with suitable titles, symbols and overflow priorities. Sheets, popovers and alerts also require transition testing. Arrangement views are optional tools for paired content. Camera-capture changes apply only to capture features.

Source: [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo).

The design guidance adds continuity of state and functionality across poses, restrained layout changes, asymmetric safe areas, and retaining controls near the content they affect. It recommends system overflow and avoiding display-specific assumptions. A larger inner display is still an iPhone environment; a regular size class must not be interpreted as proof of iPad hardware.

Source: [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

## Confirmed findings and proposed responses

### 1. Both player roots bypass native bar adaptation — high priority

Autohop `Views/RootView.swift` hides the player navigation bar. `Views/PlayerView.swift` draws its own top bar above a page-style TabView. Wireless `Wireless/RadioPlayerView.swift` does the same with `topBar(width:)` and a hidden navigation bar. These are custom horizontal content, not native toolbar or tab-bar items. Their page-style TabViews do not supply a native navigation tab bar for these controls.

Consequently, rebuilding alone will not transform those custom bars into the vertical system presentation. Move navigation and global actions into native toolbar items, giving actions both a title and symbol. Keep transport, seeking and TV Sync controls near their media rather than relocating every control into a side bar. Decide which player panel selectors remain content controls and which should use native navigation. Preserve the current panel destinations and their accessibility labels.

Audit custom image-only Back and Close helpers as well as text-only Save/Done buttons. An accessibility label should not be assumed to supply all the semantic title information needed for overflow presentation. Prefer native Back on pushed pages, cancellation placement for modal dismissal and prominent semantic placement for completion actions. Keep existing Back ownership correct; Autohop already has a central policy for its iOS 27 duplicate-Back fix.

Use the new axis and visibility APIs only when needed after native defaults are tested. toolbarVerticalEdge expresses the system's preferred edge even when no bar is visible; it is not simply a bar-visibility flag.

Sources: [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/), [toolbarVerticalEdge](https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge), [axisBehavior](https://developer.apple.com/documentation/swiftui/toolbarcontent/axisbehavior(_:)).

### 2. Autohop's player has a concrete height constraint risk — high priority

`Views/PlayerView.swift:625` estimates the total height of metadata, chapter strip, scrubber, controls and Up Next. `nowPlayingPanel` at line 729 subtracts that estimate from available height, but clamps artwork to at least 80 points. Its enclosing VStack is non-scrolling. The estimate cannot reliably cover large text, long metadata, reduced vertical space or new bar geometry.

The inline-video path separately sets video height from the full available width at 16:9. Shrinking square artwork therefore does not bound video height. Short and wide windows need explicit treatment.

Refactor the player into media and control content with a layout based on actual available width AND height. Keep all essential controls reachable through a compact arrangement or appropriate scrolling fallback. Consider media above and controls below for hands-free video, and side-by-side media/control content when space permits. Test empty state, chapters and Up Next combinations, not only a simple audio episode.

### 3. Wireless's player is resizable but not fold-aware — high priority

`Wireless/WirelessLayoutMetrics.swift` uses container width bands and caps readable widths. `RadioPlayerView.playing(size:)` already scrolls and switches between VStack and HStack. This is a stronger starting point for short displays than Autohop's current non-scrolling player.

However, the wide arrangement requires both an expansive width band and at least 760 points of calculated available width. Its artwork has minimum size assumptions. These calculations neither identify the fold nor prevent centred controls or artwork crossing it. They also use the outer GeometryReader's size rather than a direct measurement of the page after the custom top bar consumes space.

Measure the actual player content area. Choose the layout using available space, traits and active reserved regions. Retain scrolling where appropriate, and keep station identity, play/pause, Favourites and Sync reachable at every supported size. Do not simply make the width threshold match an assumed Duo screen dimension.

### 4. Neither app currently implements the new fold-region APIs — high priority

The inspected iOS sources contain no ArrangementView, reservedRegions or toolbarVerticalEdge implementation. Existing GeometryReaders provide geometry but do not by themselves avoid an internal division.

For custom content, identify active division and occlusion regions in the same coordinate space used for placement. Query active regions by default; use inactive regions only deliberately. Keep important interaction targets away from the fold, including scrubbers, play/pause, station shortcuts, Sync sliders and confirmation overlays. Decorative backgrounds can remain full bleed. Ordinary scrollable content does not automatically need to be split into two pages.

For paired media/controls, evaluate ArrangementView before writing a bespoke hinge-aware layout. Do not put it inside the existing Wireless player ScrollView. Apple's symbol documentation also cautions against nesting it with NavigationSplitView and other competing layout containers. Start from a NavigationStack-hosted content area and determine the permitted paging/scrolling structure in a prototype. A split arrangement can hide its secondary view in compact configurations, so essential actions must remain accessible in the primary view or through another route.

For video, an overlay arrangement with controls as primary and video as secondary is worth evaluating; for artwork and controls, split may fit better. These are design proposals, not adopted decisions.

Sources: [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview), [reservedRegions](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)), [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/).

### 5. Orientation policy needs reconciliation — high priority

Wireless `project.yml` and `Wireless/Info.plist` support portrait only for iPhone and all orientations for iPad. Autohop's plist declares iPhone landscape, but `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` returns the global VideoOrientationController mask. That mask starts as portrait, unlocks for full-screen video, then explicitly requests portrait on dismissal.

Therefore, Autohop's plist declaration is not sufficient evidence of unrestricted rotation; the global delegate restriction also needs review, including its effect on iPad. Avoid carrying this policy unchanged into the foldable layout. Decouple full-screen-video transitions from normal app layout and review the selection of the first active scene when multiple scenes exist.

Apple's preparation talk explains that the inner display does not honour supported interface orientations in the usual way. Portrait declarations cannot be relied on to protect these layouts from wide geometry. Add outer-display landscape support where suitable, but treat it as a product/layout decision rather than claim that removing a plist restriction alone establishes compatibility.

Source: [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

### 6. Open presentations may lose continuity — high priority

Autohop `Views/AdaptiveLayout.swift:814` and `:839` conditionally choose fullScreenCover for regular width and sheet for compact width. On a live size-class transition, that changes the presentation host's structural branch. Dismissal, re-presentation or lost local state is a risk to test, not an observed Duo failure.

Prefer stable presentation ownership. Preserve edits, focused fields, scroll position, selection and the route stack through resize. Review Menu, Up Next, podcast settings/detail, import/export, sharing, sleep timer and audio controls. Wireless also needs Favourites, Audio Controls, Sleep Timer, settings/contact routes and stats presentations checked. A fixed medium detent may be insufficient for some compact-height content; verify scrolling and keyboard behaviour.

Do not disable vertical bars globally to preserve an old sheet appearance. Consider an exception only for a specific sheet after testing. Apple's overview describes placement-dependent inner-display sheet bars; use the detailed API guidance rather than assuming every inner sheet has identical bar placement.

### 7. State and playback continuity require explicit regression tests — high priority

Autohop deliberately keeps PlayerView mounted as the NavigationStack root and uses shared playback coordinators. Preserve that ownership while rearranging content. Do not create separate players for alternate displays or branches. Keep playback position, queue, chapter, speed, trim/skip behaviour and current route stable.

Wireless holds MobilePlayer.shared above the player view. Its scene-phase handler in `RadioPlayerView` currently resets the selected pane to Playing whenever the scene becomes active. If a display transition causes an inactive/active sequence, Details or Sync could be lost. The transition behaviour requires real observation; do not assume every fold produces a scene-phase change. Review whether panel resets should be limited to deliberate return-to-player actions.

`MobilePlayer.sceneChanged` refreshes metadata/routes on activation and may reconnect requested playback while buffering. Test this during transitions to distinguish intentional recovery from duplicate restarts. Preserve deliberate Pause, selected station/stream, delay, Vocal Boost, timers, Now Playing and listening-session accounting. A resize must not create a new listening session merely because the view changed.

Autohop's high-priority seek gesture and automatic inline-video PiP trigger on scene inactivity also need specific checks during transitions. Ensure a fold does not cause an unwanted seek, PiP launch, video pause or orientation request.

### 8. Camera and extra-display features are outside the current feature scope

No AVCapture-based camera feature or camera usage-description entry was found in the inspected app sources/configuration. AVPlayer/VideoPlayer playback is not camera capture. The new camera-direction and camera-capture accessory work is therefore not required for the current apps.

Do not assume the outer screen can become an always-on second radio controller while the inner screen is in use. Apple's camera accessory example depends on an active camera session. Additional scene/accessory features require their own supported use case and availability review. Raw hinge-angle events are for optional interactions; use region/layout APIs for ordinary adaptation.

Sources: [Leverage multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/), [Build a great camera experience](https://developer.apple.com/videos/play/tech-talks/111465/).

## Implementation sequence

1. Install/select Xcode 27.1 with the required SDK and Duo support. Preserve the existing projects' uncommitted work. Capture baseline screenshots and playback behaviour before changes.
2. In Autohop, establish stable layout and presentation ownership, correct the height-constrained player and review orientation policy. Adopt native toolbar semantics and prototype the media/control arrangement with older-OS fallbacks.
3. Validate Autohop's reusable layout and navigation approach. Copy/adapt the applicable implementation into Wireless, preserving station playback, Favourites, metadata and TV Sync behaviour. Do not copy Autohop's current portrait gate or size-class presentation branch unchanged.
4. Audit the rest of both apps: Discover/charts, subscriptions/station lists, search, details, downloads, history/stats, settings, support, onboarding, sheets, popovers, keyboard and overlays. Test adaptive grids near the fold rather than assuming width-based columns are enough.
5. Update in-app support and canonical source guides alongside implemented behaviour. Autohop's current support contains a Landscape orientation section that will need revision if that policy changes. Update Wireless SUPPORT_GUIDE.md and Wireless/SupportContent.swift. Review Autohop PAGES.md and its canonical support source as part of implementation.
6. Run the release matrix below, then validate archives built with the intended SDK before describing the apps as Duo-compatible.

## Validation matrix and acceptance criteria

| Area | Required coverage | Acceptance criterion |
| --- | --- | --- |
| Geometry | Closed/open, both rotations, partially folded book/laptop, tent where applicable, repeated transitions | No clipped or unreachable controls; usable text; fold/camera do not obscure important interaction targets |
| Multitasking | Each side of inner-display Split View, narrow/wide app areas, repeated resize | Correct asymmetric safe areas, no screen-size assumptions, stable navigation |
| Bars | Native Back/Close, primary actions, overflow and panel selection on every major route | No duplicate Back; understandable symbols/titles; every action remains reachable |
| Presentations | All sheets/popovers/dialogues; keyboard visible; resize mid-edit and mid-scroll | No unintended dismissal, duplicate presentation, lost edits or focus traps |
| Accessibility | Largest accessibility text, VoiceOver, Reduce Motion, Increase Contrast, Reduce Transparency | Controls remain operable and correctly labelled; hidden panels have no stray focus targets |
| Autohop audio | Streaming/downloaded, seek in progress, chapters, queue changes, skip/trim/speed, pause | Correct item and position; no view-induced restart or loss of user settings |
| Autohop video | Inline/full screen, PiP, return from PiP, open/close/rotate while playing | Correct player ownership; no unexpected PiP/pause, orientation crash or distorted media |
| Wireless audio | AVPlayer and enhanced engine, buffering/reconnection, paused state, alternative streams | Playback intent preserved; no duplicate engine start or unwanted resume |
| Wireless Sync | Delay adjustment/slider interaction, pane selection, folding during playback | Sync state and measured delay preserved; controls avoid the fold |
| System integrations | Bluetooth/AirPlay/headphones, interruptions, background/lock, timers, Now Playing, stats | Playback and accounting remain correct across display and lifecycle changes |
| Existing platforms | Supported older iOS versions, standard iPhone, iPad window sizes, compatible Mac | No regression from new availability-gated code; pointer/keyboard actions still work |

Use the Duo simulator/Device Hub for pose and layout verification. Use physical Duo hardware for audio-route continuity, interruptions, background recovery and real fold/display transitions. Simulator results cannot certify these behaviours. Inspect actual App Store archive SDK/build metadata; an installed Xcode version is not proof of how an existing uploaded build was produced.

[Apple's iPhone Mirroring technote](https://developer.apple.com/documentation/technotes/tn3210-optimizing-your-app-for-iphone-mirroring) is useful supplementary coverage for custom gestures, trackpad/mouse scrolling and sheet dismissal. It is not a substitute for Duo pose testing.

## Review limits

This review examined live Apple overview/HIG/API documentation, relevant sections of the six linked Duo Tech Talk transcripts, current app roots, adaptive/player/navigation/presentation code, orientation configuration, scene handling and local SDK/simulator inventory. It found source-level risks; it did not reproduce them on Duo. The older general WWDC talks were not exhaustively reviewed. No builds, automated test suites, visual app sessions, physical-device tests or App Store uploads were performed in this review.

Wireless had substantial pre-existing tracked and untracked work; Autohop's worktree was clean at inspection. Only this review document was added. No station-directory research was involved, so no directory database changes were required.
