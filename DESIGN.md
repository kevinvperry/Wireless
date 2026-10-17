# Wireless — Design System

Active development targets `Wireless`, the native SwiftUI iOS app for iPhone, iPad and compatible Mac use. `AGENTS.md` governs development scope.

Version 1 specification · 10 October 2026

This document defines Wireless for iPhone, iPad and compatible Mac use. Its tagline is “Fine Tuning Your Radio Presets”. It is the design contract for the first test build. See MOBILE_TESTING.md for implementation and validation scope.

Exact cross-app measurements and the completed element-by-element comparison are recorded in `UI_AUDIT.md`. `WirelessLayoutMetrics` mirrors Autohop’s adaptive navigation and list width bands. iPhone presentation is portrait-only; iPad and compatible Mac presentation may rotate or resize.

The Playing pane follows Autohop’s compact player hierarchy: icon-based pane controls, artwork sized to the available width, programme and station copy, a live-position bar, central transport control and a bottom audio-action row. The current playback state appears at the lower-left of the position bar; the lower-right identifies the live edge or TV Sync delay. While buffering, this same bar and its right caption show buffer completion rather than adding another progress bar. Do not repeat playback-state text beneath Play/Pause. The functional Sleep Timer mirrors Autohop’s fixed-duration presets, countdown badge, five-minute extension, cancellation and gradual 30-second fade before playback pauses. The Sleep Timer sheet ends with a Sleep Schedule row that pushes Autohop’s Sleep Schedule page (intro card, Active Hours, Ask Every, Your Schedule and How Sleep Schedule Works) inside the sheet and expands it to the large detent. End of Episode is omitted for live radio. During the active hours, Autohop’s bed-icon Sleep Schedule pill sits beside the Discover button in the top bar, showing the minutes until the next check-in while counting (icon only when paused or idle) and opening the Sleep Schedule page. While a check-in is pending, the player shows Autohop’s full-screen “Are you still listening?” overlay with its large Still Listening button. The top-right Favourites control mirrors Autohop’s Up Next counter with an outlined heart and the current saved-station count. The action row uses Autohop’s 96-point leading and trailing zones, 44-point square function controls and full-width audio-source selector. The trailing action is one rectangular Favourite or Unfavourite station button. Beneath this row, two equal glass tiles replace Autohop’s Up Next card and provide immediate playback of the first two saved favourites after excluding the selected station.

`DESIGN.md` owns visual patterns; [PAGES.md](PAGES.md) owns page names, navigation and page behaviour. Use Australian English throughout.

## Reference and authority

The visual references are Autohop's `DESIGN.md` and `PAGES.md` in the Autohop repository, particularly Main Player Page, Adaptive viewport layout, Navigation rules and Player Sheets. Reuse suitable Autohop SwiftUI components and supporting code after reviewing their dependencies. Do not import podcast-specific behaviour simply to reproduce its appearance.

Autohop's references contain historical descriptions alongside later updates. Follow its permanent Player-root navigation contract rather than the older page-table description of Player as a modal overlay. Its dark-only appearance and purple accent are explicit requirements here.

## Confirmed scope

- Support live-radio playback: SEN 1116, HLS/MP3 selection, adjustable audio delay, buffering, measured delay, automatic delay correction and programme guide.
- Use modern Swift and SwiftUI, following current Apple platform conventions and targeting the latest iOS release. The iOS deployment target is 26.0; use Xcode 27 or later for the current source.
- Support iPhone, iPad and Mac in the same manner as Autohop. Its documented Mac model is the compatible Designed-for-iPad app; verify project configuration before implementation.
- Continue playback in the background and when locked. Foreground and background scene changes must retain the active decoder, buffered audio and current Sync position. Recover automatically after reception returns, preserving the chosen delay and respecting a manual Pause.
- Support Lock Screen, Control Centre, headphone controls and AirPlay.
- Provide a top-right Favourites shortcut backed by stable directory station IDs. A first install begins without an implicit favourite.
- Store favourites and delay locally. Discover uses the Cloudflare directory and caches its last complete revision for offline browsing. iCloud synchronisation remains outside the current scope.

## Core visual patterns

| Pattern | Wireless contract |
|---|---|
| `ColorScheme-Dark` | Force `.preferredColorScheme(.dark)` for app-owned pages and sheets. No light theme. System-owned surfaces retain system presentation. |
| `Accent-Purple` | Use SwiftUI `Color.purple` for primary actions, active indicators, selected controls and progress. Do not invent a different brand purple. |
| `Canvas-Black` | Full-viewport black background, including safe areas. White primary text and subdued secondary text. |
| `Glass-Control` | Match Autohop's native glass controls where supported; use its material/tinted fallbacks if required by the chosen deployment target. |
| `Glass-Card` | Restrained rounded cards for related information; black remains the dominant canvas. Typical settings card radius 12 pt with 20 pt internal padding. |
| `NavTitle-Inline` | Centre inline titles on pushed pages and sheets. The Player has its own custom top bar. |
| `NavBack-Standard` | Exactly one Back control on pushed pages; prefer the platform's native navigation behaviour. |
| `SheetClose-Standard` | Informational sheets use an accessible top-right cross and drag-to-dismiss. |
| `Sheet-MaterialBackground` | Match Autohop's regular-material sheet background, approximately 20 pt presentation corners and hidden default scroll backgrounds. |
| `Readable-Inner-Content` | Constrain inner content while backgrounds and scrolling hosts fill the viewport. |
| `MiniPlayer-Persistent` | Secondary pushed pages retain access to playback and return to the permanent Player. |

### `Launch-Wireless`

Bridge Apple’s static launch screen into a short SwiftUI brand animation rather than exposing a blank black frame. The system launch screen centres the cream scale and red tuning needle on black. The animated continuation uses the same geometry: scale marks pulse like a radio signal, the red needle tunes into its final app-icon position, then the composition fades into the prepared root page after approximately 1.2 seconds. Show “Wireless” and “Fine Tuning Your Radio Presets” only within this opening animation; keep both off the main Player. Reduce Motion keeps the complete mark and copy visible without repeating movement.

Colour never carries meaning alone. Pair active, reconnecting and error states with text and suitable SF Symbols. Treat Autohop's dim grey examples as visual references, not permission to make essential information unreadable.

## Player composition

The Player is the permanent navigation root. A first install with no saved favourites or last-played station opens Discover; later launches restore the last-played station on the Player without starting audio. Preserve Player identity while navigating or presenting sheets; playback belongs to a shared service, not a view lifecycle.

Adapt Autohop's main player in this order:

1. Custom top bar with a quiet leading navigation control and the purple Favourites shortcut at the top right.
2. Large square station artwork with ambient purple glow.
3. Centred programme title and station name.
4. Basic playback status, with no editable delay controls on Playing.
5. Prominent central Play/Pause control with buffering or recovery status nearby.
6. Audio controls and a centre-aligned AirPlay/output selector.
7. An optional Details pane for station and programme information when available.

The Player orders its panes as **Playing**, conditional **Details**, then **Sync**. Playing contains basic playback controls; Details appears only when the selected station supplies description, website or programme information; Sync contains the full audio delay slider and half-second adjustment buttons. Keep every delay-changing control off Playing to prevent accidental changes. Changing panes preserves playback and the selected delay. Opening or returning to the Player selects Playing.

The remaining ordering is a proposed radio adaptation. It preserves the reference's visual hierarchy without implying that podcast chapters, downloads, queues, archive or speed controls are approved version 1 features.

### `TopBar-Player`

Use Autohop's three-zone composition and shared responsive sizing. The top-left control opens Discover. The centre contains the **Playing / Details / Sync** pane selector, matching Autohop's selected neutral-glass capsule and subdued unselected icon treatment. Details uses Autohop's `info.circle` symbol and is omitted when no details exist. Playing is selected by default. Pane switching works like Autohop: tap or swipe horizontally using a paged TabView, with page dots hidden.

Replace Autohop's Up Next pill with a `heart.fill` icon and the label Favourites where space permits. On narrow layouts an icon/count presentation must retain the accessibility label “Favourites”. Opening this button shows the Favourites sheet; it does not toggle the current station's favourite status. Any count represents saved stations, never queued programmes.

### `Artwork-Player`

Use station artwork rather than podcast artwork. Match Autohop's square shape, approximately 20 pt corners and subtle white 0.1-opacity border at 0.5 pt. Its ambient radial glow uses purple at 0.34 opacity, centred near `(0.5, 0.66)`, fading to clear.

Scale artwork to the available space after reserving controls and text. Autohop's phone baseline uses 22 pt horizontal gutters. Do not allow artwork to force controls off screen. At large text sizes or short landscape heights, use a scrollable or adaptive arrangement.

Broadcaster artwork is composited over a white surface so transparent logo elements never reveal the app’s purple fallback colour. Fully opaque artwork covers that surface normally. Missing artwork uses a restrained purple surface and waveform. Failed artwork loading never blocks playback.

Use the same station artwork in every station identity surface: the full player, Discover and Favourites rows, favourite shortcut tiles, the navigation mini-player, Control Centre and the device Lock Screen. System Now Playing artwork is rendered onto an opaque white square before publication so transparent broadcaster logos remain legible outside the app.

### `ProgrammeCopy-Player`

Centre a bold programme title when available, otherwise the station name, over smaller network and location copy. Autohop's phone baseline is 16 pt bold primary copy and 12 pt secondary copy; implement scalable typography and allow wrapping rather than fixed-height clipping.

Programme metadata belongs in Details rather than a card at the bottom of Playing. Guide metadata describes the broadcaster's live schedule and may lead delayed audio; do not claim that it identifies the exact audible programme.

### `Panel-Sync` and `DelayControl-Sync`

Place the complete **Audio delay** control exclusively in the Sync pane. Include the slider, selected numeric delay, half-second minus/plus buttons, measured delay, buffering feedback and explanatory text. This is a delay setting, not an episode timeline or recording seek bar. The Playing pane has no slider, adjustment buttons or delay-changing gestures.

- Range: 0–30 seconds, in 0.5-second steps, with minus/plus actions and a readable numeric value.
- Persist the selected delay locally and retain it across stream changes and recovery.
- Persist the selected stream independently for each station and restore it on relaunch. Fall back to the station's preferred stream only when there is no saved choice or that source is no longer available.
- Explain that selected delay is additional to broadcaster, network and audio-output latency.
- Preserve compatible AAC HLS's minimum buffering/headroom semantics: at least 2.5 seconds; for selections of 2.5 seconds or more that headroom sits within the selection.
- Keep compatible HLS at its chosen retained-packet offset without periodic automatic output-queue rebuilds. HLS measurements move at segment boundaries and must not trigger repeated micro-corrections; explicit delay changes still reposition playback. Continue sustained-lag correction for continuous MP3 and AAC sources.
- Show measured stream delay separately from the selected value. Never imply that this measures AirPlay/AirPods output latency or alignment with a television picture.
- Increasing delay may pause audio to accumulate the buffer; reducing it moves forward. Display a clear buffering state when necessary.

### `Controls-Player`

Match Autohop's central white play/pause symbol on a purple-tinted glass circle, using its 76 pt circle and 28 pt symbol as phone baselines. Retain the subtle purple glow (0.35 opacity, 14 pt radius). Scale through shared metrics.

Keep half-second delay adjustments exclusively in Sync, with explicit labels. Do not reuse podcast skip symbols with misleading 15/30-second semantics. During recovery the user must still be able to cancel playback intent with Pause.

### `AudioRow-Player`

Reuse Autohop's compact glass action style: roughly 18 pt bold purple icons, neutral glass when idle and purple-tinted glass with white icons when selected. A 44 × 32 pt visual pill needs an accessible hit region of at least 44 × 44 pt.

Proposed version 1 row: Audio Controls action and centred system route picker. Preserve useful spacing instead of adding unapproved features to fill Autohop's five-button arrangement.

Display the real system route name beside `airplayaudio`; truncate a long name rather than removing it. Refresh after route changes and foreground activation. Use the native route picker and distinguish route changes from network recovery.

## Lists and favourites

Station rows use square artwork, primary station name, secondary description and a separate favourite action. Use a purple active indicator plus text/icon for the playing station. Give Play and Add/Remove Favourite separate accessible actions.

Favourites opens as a full-height regular-material sheet matching Autohop Up Next. It has no search or directory filters. Rows use a leading position or purple play marker, square station artwork, primary and secondary copy, and a trailing remove-favourite control. A Reorder capsule mirrors Autohop Subscriptions: entering reorder mode changes the control to Done, shows stable drag handles, hides competing favourite actions and saves the resulting order locally.

The Player’s two favourite shortcut tiles use this same persisted order. Exclude the selected station before taking the first two playable favourites: playing favourite 1 therefore shows favourites 2 and 3, while playing favourite 2 shows favourites 1 and 3. Selecting a tile starts that station immediately. If fewer than two other playable favourites exist, show only those available and retain the two-column alignment.

Station artwork is always edge-to-edge within its square frame, using aspect-fill cropping and continuous rounded corners. Do not add internal padding or a visible white inset around artwork on the Player, favourite shortcuts, Favourites, Discover or the mini-player. A white backing remains behind transparent pixels only. Lock Screen artwork uses the same aspect-fill treatment.

Discover lists published stations from the Cloudflare directory. Do not add a station to Favourites implicitly. A first install with no favourites opens Discover; a station selected for playback becomes the persisted last-played station independently of favourite membership.

Removing a favourite does not stop playback or remove the station from Stations. Empty Favourites shows a brief explanation and an action to Stations. Future catalogue growth must not require changing the Player's top-right shortcut or station identity model.

## Adaptive layout and accessibility

Reuse Autohop's available-container-width approach. Its reference bands are narrow below 340 pt, standard 340–499 pt, wide 500–699 pt and expansive from 700 pt. Centralise these metrics; do not infer layout from device names or screen bounds.

Use actual window and presentation width, including iPad multitasking and resizable Mac windows. Scale artwork, typography, controls, spacing and supporting metadata together. Readable list content may use Autohop's approximately 900 pt column/860 pt inner surface as a starting point; the player should retain balanced proportions rather than stretching controls across a large window.

Support Dynamic Type, VoiceOver, keyboard focus, pointer input, Reduce Motion and Reduce Transparency. Do not require swipes for essential actions. Keep delay values monospaced, label all icon buttons and avoid announcing every countdown tick. Ensure the top bar remains usable at large text sizes.

## Playback state presentation

| State | Visible treatment | Available action |
|---|---|---|
| Ready/paused | Station information and Play | Start playback |
| Connecting | “Connecting…” with restrained progress | Pause/cancel requested playback |
| Buffering | “Building audio delay…” with meaningful progress when measurable | Pause |
| Playing | Pause plus selected and measured delay | Pause or adjust delay |
| Reception lost | “Waiting for connection…”; keep station and delay visible | Pause to cancel automatic resume |
| Recovering | “Reconnecting…” then buffering if required | Pause |
| Source unavailable | Clear explanation; retain context | Retry or select the other stream |

Automatic resume is driven by the user's playback intent. Network recovery must not override a later manual Pause. Rebuild an appropriate live buffer after an outage rather than replaying stale packets to imitate continuity. Retry with bounded back-off while playback is requested; connectivity changes can trigger a fresh attempt. Do not promise recovery after an explicit force-quit or system termination.

## Reuse and validation

Review Autohop's `Views/PlayerView.swift`, `Views/AdaptiveLayout.swift`, navigation helpers, glass helpers, mini-player, route picker and `NowPlaying/NowPlayingService.swift` as reuse candidates. Review Wireless's existing stream engine, delay correction, player and programme guide for shared radio behaviour. These are candidates, not claims that components have been copied or work unmodified on iOS.

Before declaring version 1 complete, validate visual layouts on iPhone, iPad and a compatible Mac; audio/background behaviour and interruptions on physical devices; brief and prolonged cellular loss; manual Pause during recovery; HLS/MP3 switching; delay correction; Lock Screen/headphone actions; and real AirPlay routing. A simulator build alone is insufficient evidence for those behaviours.

## Deferred and unresolved

Deferred by the user: a many-station library and iCloud sync. CarPlay, widgets, recording, podcast features and Apple TV app support have not been requested; AirPlay to Apple TV is in scope.

Continue asking yes/no questions one at a time for unresolved product choices. Confirm remaining proposed navigation and any additional feature before treating it as user-approved scope. Verify exact OS/deployment and Mac distribution configuration during implementation.

## Sync on/off — 10 October 2026

The Sync pane has a persistent **Sync audio to picture** toggle. Existing installations default to on, retaining their previous behaviour. Off hides the saved-delay tile and all other Sync controls. On reveals a **Saved audio delay** tile with the slider, half-second buttons and novice guidance explaining whether to increase or decrease the delay. Playback transport remains on the Playing pane and is not duplicated in Sync. Switching modes never overwrites the saved delay or starts paused playback.

While a compatible HLS stream is accumulating enough audio for TV Sync, describe the state as **Building an audio buffer** and enable the controls automatically when ready. Do not present this temporary preparation period as an incompatible or unsupported stream.

With Sync off, both mobile playback engines return to ordinary live playback, establish a short reliability buffer and stop measuring or correcting TV delay. Compatible MP3, AAC and AAC HLS streams rebuild their Audio Queue output from five seconds behind the newest retained packets. Other HLS streams recreate their live item with AVPlayer’s automatic stalling protection and a five-second preferred forward buffer. Turning Sync back on deliberately reapplies the saved delay once before normal sync behaviour resumes.

The mobile packet engine retains MP3, AAC and AAC HLS elementary-stream packets for Sync, including live HLS playlists that do not advertise an AVPlayer seekable window. AAC HLS needs at least 2.5 seconds of segment headroom. Other HLS containers use AVPlayer and support Sync only when the broadcaster publishes a seekable live range. With Sync off, that fallback path skips app-driven seeks and requests five seconds of forward buffering with automatic stall minimisation. Original stream audio is decoded without adding lossy transcoding; this does not improve the broadcaster's bitrate or remove source/network faults.

The live-stream adapter is `Wireless/DirectoryAudio.swift`.

## Discover region tiles — 10 October 2026

Mobile Discover opens with adaptive dark-purple tiles in this exact reading order: National, Melbourne, Sydney, Brisbane, Adelaide, Perth, Hobart, Canberra, Darwin, Other. The grid scales from two phone columns to additional columns in wider windows. Tiles use rounded 18-point surfaces, purple SF Symbols and semantic station-region labels. Search remains above the grid; entering a global query shows matching station rows instead of tiles.

Networks and non-capital locations use full-page tile browsers rather than pop-up menus. Two prominent **Networks** and **Other Locations** cards appear before the regional grid so both routes remain visible on a phone without navigating a fragile menu. Their adaptive tiles show station counts, use the same purple gradient and rounded geometry as the capital tiles, and lead to a scoped station list. ABC, Triple M, Hit Network, KIIS, Gold, Nova and Smooth insert another matching tile level for their official service groupings. **Community and Specialist stations** inserts tiles for Community, Religion, Foreign Language, Country Music, Indigenous, Arts & Music, Radio Reading, Youth & Education, Seniors and LGBTQIA+ and is ordered second last. **Not yet categorised** is always the final network tile. A compact context card identifies the active network, sub-network or location above those results.

Tapping a tile pushes its station list with the region as the inline title, native Back and the shared mini-player. The 53 flagship station identities and their per-city ordering are taken from `research/australian-radio/capital-cities.md` and its companion JSON. These appear first in the documented order: ABC Local Radio, SEN, Hit Network, Triple M, Nova, Smooth, KIIS, Gold, Talk radio. Absent city/network combinations do not create placeholder rows. Remaining known main-network stations follow, then other stations alphabetically.

National includes explicit national metadata and identifiable ABC national/SBS services. A missing city or membership of a national network alone does not imply nationwide coverage: unassigned and regional stations fall under Other. Curated city identities override incomplete catalogue city metadata. All catalogue stations remain reachable, including unclassified records. The Discover view and region policy live under `Wireless/`.

## Live song information

During normal playback, accepted song metadata uses a bold title-and-artist top row with the station name below, following Autohop’s primary-content/source hierarchy. The mini-player uses the same ordering. Recognised commercial-break and technical playout metadata is rejected centrally before it reaches in-app or system displays; rejection clears the previous song and restores station information. TV Sync continues to show station/programme information. Album information is retained for the mini-player and system metadata rather than crowding the main two-row heading.
