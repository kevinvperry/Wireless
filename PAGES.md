# Wireless — Page Reference

Active development targets `Wireless`, the native SwiftUI iOS app for iPhone, iPad and compatible Mac use. See `AGENTS.md`.

The Playing pane does not display the Wireless name or tagline. Its top pane controls use Autohop’s selected icon-and-label treatment, while the inactive pane shows its icon alone. The top-right Favourites button uses an outlined heart and saved-station count in the same layout as Autohop’s Up Next counter. Station artwork fills the same available-width footprint as Autohop artwork. A read-only progress bar places the current playback state at lower-left and the live edge or configured TV Sync delay at lower-right. During buffering, that same bar represents buffer completion and the right caption shows its percentage; no separate buffering bar appears. Playback state is not repeated beneath Play/Pause. The bottom action row copies Autohop’s 96/centre/96 geometry: 44-point Audio Controls and Sleep Timer buttons, the full-row Apple audio-route selector, and a rectangular Favourite or Unfavourite station control. Two side-by-side glass tiles beneath it show the first two ordered favourites after excluding the selected station; selecting either tile immediately starts it. The Sleep Timer sheet’s Sleep Schedule row opens the Sleep Schedule page within the sheet. During Sleep Schedule active hours, a bed-icon pill beside the Discover button shows the minutes until the next check-in and opens the same page.

Version 1 specification · 10 October 2026

This is the proposed page and navigation contract for the new iPhone, iPad and Mac-compatible app. The first test build now implements this page structure; see MOBILE_TESTING.md for validation scope. [DESIGN.md](DESIGN.md) defines the Autohop-derived dark appearance, purple highlights and shared visual patterns.

The user has confirmed uninterrupted background playback, automatic recovery after reception loss, system/headphone playback controls, AirPlay, directory browsing and a functioning top-right Favourites shortcut. Moving between foreground and background retains the existing decoder, buffer and Sync position rather than restarting the stream. Favourites, last-played station and selected delay are local.

App opening begins with the Wireless radio-scale mark and current tagline over black. Its short animation fades into the already prepared launch destination; it does not alter first-install Discover routing or later restoration of the last-played station.

## Page table

The page table retains conceptual view names; the first build implements these surfaces in RadioPlayerView.swift.

| Visible name | Proposed view | Presentation | Purpose |
|---|---|---|---|
| Player | `RadioPlayerView` | Permanent root | Playing (default), conditional Details and Sync panes. Details appears only when information exists for the selected station. |
| Favourites | `FavouritesView` | Full-height sheet from Player top right | Working favourite-station shortcuts with persistent drag reordering. Replaces Autohop's Up Next entry point. |
| Stations | `StationsView` | Pushed page from Player leading control | Version 1 station entry, Play and Add/Remove Favourite; future catalogue destination. |
| Audio Controls | `RadioAudioControlsSheetView` | Sheet from Player audio row | HLS/MP3 selector and concise explanation of selected/measured delay. |
| AirPlay/output picker | System-owned view | Native route presentation | Select an available audio output. |
| Lock Screen / Control Centre | System-owned media surface | Outside app navigation | Station/programme metadata and Play/Pause. Headphone controls invoke the same playback actions. |

The top-right Favourites shortcut and top-left navigation to Discover are confirmed requirements. A first install with no favourites opens Discover. Once a station has played, later launches restore that station on the Player.

## Navigation structure

```text
Player — permanent root; opens on Playing
├── Playing — default pane; basic playback controls
├── Details — conditional pane; station and programme information
├── Sync — pane; full delay slider and half-second adjustment buttons
├── Favourites — top-right sheet
│   ├── Play saved station → dismiss to Player
│   └── Browse Stations → dismiss sheet, then push Stations
├── Stations — leading navigation control
│   └── Play station → return to Player
├── Audio Controls — audio-row sheet
└── AirPlay — native system route picker

External system surfaces
├── Lock Screen / Control Centre
└── Headphone playback controls
```

Playback survives every navigation transition. Sheets do not create another player service. Pushed pages have one Back control and one persistent mini-player; the Player and its own sheets must not gain duplicate mini-players. Returning through the mini-player clears pushed navigation to Player and selects Playing. Opening another sheet first dismisses the existing one.

## Player

The Player is shown with Playing selected when a last-played station exists. Opening the app does not automatically start audio. A first install with no saved favourites or last-played station opens Discover instead of an empty Player.

### Appearance and content

Follow Autohop's black full-screen composition, purple ambient artwork glow, centred title/subtitle and large circular purple Play/Pause control. Match its top-right glass pill position with Favourites instead of Up Next. See `Artwork-Player`, `Panel-Sync`, `DelayControl-Sync` and `Controls-Player` in DESIGN.md.

### Playing, Details and Sync panes

The centre of the Player's top bar orders **Playing / Details / Sync**, following Autohop's pane-selector styling and using its `info.circle` Details icon. Details is omitted when the selected station has no description, website or programme information.

**Playing** is the default pane. It contains artwork, programme/station information, basic Play/Pause controls, recovery/buffering status and audio routing. It contains no audio-delay slider, half-second adjustment buttons or delay-changing gestures. This separation prevents accidental sync changes during ordinary playback.

**Sync** contains the full Audio delay slider, selected delay value and half-second minus/plus buttons. The range is 0–30 seconds in 0.5-second steps. Show measured stream delay separately, along with buffering feedback and the explanation of HLS headroom and downstream audio latency. There is no fabricated episode duration, seek timeline or podcast queue.

Switching panes does not change delay or interrupt playback. Opening or returning to Player selects Playing; switch between Playing and Sync by tapping the pane name or swiping horizontally, identically to Autohop. Use a paged presentation with hidden page-indicator dots and keep the selected label synchronised with the visible pane. No extra confirmation or swipe restriction is required.

Details shows available station description, location, state, frequency, region, network, genres, contact phone numbers, email, website and live schedule information. Programme lookup errors do not stop the stream, and Playing has no programme-guide card.

### Playback behaviour

- Remember the selected stream for each station. Relaunching the app or returning to a station restores that station's last valid HLS, MP3 or AAC choice; use the preferred directory stream only when no saved choice exists.
- Connect and prepare the buffer on launch while foregrounded; audio starts on Play. Do not assume iOS permits indefinite background buffering while paused.
- Persist selected delay; changing source reconnects with a fresh buffer while preserving delay and playback intent.
- Increasing delay waits for sufficient audio; reducing delay jumps forward.
- Foreground Pause silences playback while the existing buffer policy can continue. Subsequent Play uses the current stream position with the chosen delay, not the moment at which Pause was pressed.
- Preserve automatic correction of accumulated excess delay. The controller corrects when measured delay exceeds the target by at least 0.5 seconds for two seconds; validate this behaviour in the playback engine.
- Show measured delay only when meaningful. Its measurement boundary excludes downstream wireless/audio-output latency.
- For compatible HLS, retain the chosen packet offset without periodically rebuilding the output queue. Segment-boundary timing naturally moves in steps, so automatic lag corrections would create audible micro-stutters. Explicit delay changes still reposition the stream. Continuous MP3 and AAC streams retain sustained-lag correction.

### Reception loss and automatic resume

Retain the selected station, source and delay during an outage. Show Waiting for connection or Reconnecting instead of requiring repeated Play taps. Resume automatically when the stream is usable if the user still intends playback, rebuilding the selected delay as required.

A manual Pause cancels pending automatic playback, including callbacks from older retry attempts. Source changes also invalidate obsolete recovery work. Handle audio interruptions and headphone removal separately from signal loss; network recovery must not override a route/interruption pause that requires user action. Exact interruption policy requires physical-device validation.

If the app is terminated, do not claim that it can resume by itself. Background recovery while the process is allowed to run is a version 1 acceptance requirement to test, not an implementation guarantee in this document.

## Favourites

Open from the Player's top-right Favourites pill. Match Autohop's Up Next sheet material, dark rows, artwork alignment, inline title and cross close control.

Open at the same full-sheet height as Autohop Up Next. Do not show search, network filters, city filters or directory refresh controls. Show saved station rows with their order number, artwork, station details, separate Play action and Remove Favourite action. Selecting a station for playback dismisses the sheet to Player. Removing the currently playing favourite leaves playback running. Preserve favourite IDs and their user-defined order locally across launches.

The Reorder control mirrors Autohop Subscriptions: it changes to Done, reveals stable drag handles and temporarily replaces the row favourite buttons. Dragging a handle onto another row updates the visible list immediately and persists the order.

Discover supplies published directory stations. Do not add any station to Favourites on first launch. With no favourites, show “No favourites yet” and “Browse Stations”. Do not render fake stations or disabled future-library rows.

## Discover (Library)

The Player’s leading control opens Discover. Its top-level page has global station search, side-by-side Search by Network and Search by Location tiles, followed by large Music, News, Sport and Community & Specialist tiles. Search by Network excludes Community & Specialist because that destination has its own top-level tile. Search by Location opens National, capital-city, Other Locations and State tiles. Music opens the searchable controlled-genre page without News or Sport; those two genres open their station lists directly. Community & Specialist opens its ten specialist category tiles. Genre assignments are retained in the offline catalogue snapshot. Selecting most networks opens its scoped station list. ABC, Triple M, Hit Network, KIIS, Gold, Nova and Smooth first open adaptive sub-network tiles: ABC by service family; Triple M by Metro / Regional / Music / Sport; Hit Network by Metro / Regional / Music; and KIIS, Gold and Smooth by Metro / Music. Each row offers Play and a separate favourite toggle. Refresh on entry; check the catalogue revision before downloading all pages. Keep a complete local snapshot for offline browsing and show a retryable error when refresh fails. Never replace the cache with a partial download.

Favourites retain stable station IDs and updated metadata. A removed catalogue station stays visible in Favourites as unavailable so the user can remove it deliberately. Favourites and station browsing share the same controls and data source.

Use stable station identity independent of stream format: HLS and MP3 are sources for the same station, not duplicate favourites. Tapping a favourite control changes only favourite membership; tapping Play starts that station and returns to Player.

A bottom mini-player exposes playback state and returns to Player. Its purple backing covers the bottom safe area, following Autohop's shared mini-player pattern.

## Audio Controls

An informational/settings sheet with immediate local changes and a top-right cross, not a draft requiring Save.

Offer every selected station's compatible directory stream alternatives with format and measured quality. MP3, AAC and AAC HLS elementary streams use the buffered decoder, so Sync does not depend on the broadcaster publishing an AVPlayer seekable range. Other HLS containers use Apple’s native decoder and support delay only within the broadcaster’s seekable range. Unsupported formats are labelled as unavailable rather than pretending to play.

Do not add podcast speed, silence trimming, archive or download controls solely because Autohop's sheet contains them.

## System playback surfaces

Publish useful station and programme metadata plus white-backed station artwork through the system's Now Playing integration. Expose Play/Pause consistently across the app, Lock Screen, Control Centre and headphones. Do not advertise seek/skip commands for unsupported live-radio operations or report a fabricated finite duration.

Use the native AirPlay picker from the Player. Retain a visible active route name, including personalised device names. AirPlay output can introduce latency beyond the app's measured stream delay; never label that measurement as television synchronisation accuracy.

## Settings and Support

Open Settings from the gear button in the top-right corner of Discover. Settings uses Autohop's dark Form presentation, purple symbols, glass section surfaces and 48-point section spacing. It contains Playback settings, the Wireless Support guide, TestFlight sharing and an About section with View Source on GitHub, MIT Licence, Open Source Acknowledgements and app version information. The About footer identifies the MIT licence for original code and documentation and the MPL-2.0 exception for Vocal Boost. Hidden Stream Diagnostics remains available through the existing developer unlock.

**Wireless Support** opens a topic list modelled on Autohop's Support page. Each row uses a purple icon tile, title and short summary. Selecting a topic pushes a readable guide page containing headings, numbered steps, bullets, tinted callouts and glass metadata cards. Its canonical user-facing content is maintained in `SUPPORT_GUIDE.md` and mirrored by `Wireless/SupportContent.swift`; update both together when supported behaviour changes.

## Page acceptance checklist

- Dark appearance and purple actions are consistent across Player, sheets and pushed pages.
- Favourites is functional at the top right and has a working empty state.
- Player opens on Playing; all delay adjustments are confined to Sync. Switching panes preserves playback and delay.
- Navigation and sheets preserve audio without duplicate player instances or Back controls.
- Stream selection, audio delay and programme information work in the Wireless app.
- Recovery after brief and prolonged reception loss preserves delay; Pause during recovery prevents unwanted resume.
- Background, lock, headphone and AirPlay behaviour is verified on physical devices.
- iPhone, iPad multitasking, landscape, large text and compatible Mac window layouts remain usable.
- Local settings survive relaunch; no iCloud dependency is introduced in version 1.

Record implementation, build, simulator, physical-device and external-route evidence separately when these pages are built.


## Directory integration — 10 October 2026

Wireless uses the public read-only Worker API; no editor credentials are included. The player and system Now Playing metadata follow the selected station. SEN programme information is shown only for SEN 1116. Changing stations stops the previous decoder before starting the next. Failed directory streams try compatible alternatives; exhausting them leaves an explicit retryable unavailable state. Audio still requires an internet connection; offline browsing does not imply offline audio.

## Sync toggle — 10 October 2026

At the top of Sync, **Sync audio to picture** enables or disables synchronisation. Its state is saved locally, independently of the saved delay. When off, this is the only tile shown. Turning it on reveals the **Saved audio delay** tile, its slider, half-second controls and plain-language adjustment guidance. The Sync pane has no playback transport button; playback remains controlled from Playing. Turning Sync off leaves the saved TV-delay value unchanged, returns to the broadcaster’s live stream and establishes a short reliability buffer before playback resumes. Playing retains its existing controls and swipe/tap navigation.

## Discover regional browsing — 10 October 2026

Player → Discover → National / Melbourne / Sydney / Brisbane / Adelaide / Perth / Hobart / Canberra / Darwin / Other.

Discover initially offers prominent Networks and Other Locations routes followed by these ten tiles in the stated order. Global search still searches the complete directory. A region has its own scoped search and prioritised station list; Back returns to Discover. Sydney, Melbourne, Brisbane, Adelaide and Perth start with a **Top Rating Stations** section ordered by their supplied 15 October 2026 ratings results, followed by the remaining stations alphabetically. Network and location routes first show searchable adaptive tiles with station counts, then a scoped searchable station list. Non-favourite station lists expose the native alphabetical section index and allow the final row to scroll fully above the mini-player. Play returns to the main Player, and favourite actions keep their existing behaviour. The mini-player remains available on every Discover destination. Favourites retains its flat, manually ordered list without search or filters.

Capital-city priorities come from `research/australian-radio/capital-cities.md`; National and Other classification rules are recorded in DESIGN.md. Catalogue errors retain saved content and retry access; an empty region displays the existing no-stations state rather than inventing streams.

## Live song information

During normal playback, accepted song metadata uses a bold title-and-artist top row with the station name below, following Autohop’s primary-content/source hierarchy. The mini-player uses the same ordering. Recognised commercial-break and technical playout metadata is rejected centrally before it reaches in-app or system displays; rejection clears the previous song and restores station information. TV Sync continues to show station/programme information. Album information is retained for the mini-player and system metadata rather than crowding the main two-row heading.
