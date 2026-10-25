# Wireless Support Guide

This document is the source for the in-app Wireless Support page. User-facing support copy should remain consistent with the behaviour described here and use Australian English.

## Getting Started

Wireless lets you discover Australian radio stations, save favourites and return quickly to the stations you listen to most.

1. Open **Discover** from the player.
2. Browse a capital city, network, National stations, another location or a state and territory.
3. Tap a station to select it and begin playback.
4. Tap the heart button to save the station to **Favourites**.

On a first installation with no saved station, Wireless opens Discover instead of presenting an empty player. Later launches restore the last selected station without starting audio unless **Auto Resume** is enabled.

## Discovering Stations

The Discover page provides several ways to browse the directory:

- **Search by Network** begins with an alphabetical grid of major broadcasters using network artwork maintained in the Wireless directory. **All Networks** then lists every network, including the featured broadcasters, alphabetically. ACE Radio Network appears as **ACE Radio**, ARN as **ARN Regional** and Hit Network as **Hit**. Networks with distinct services open a second set of tiles. Within ABC, **Triple J** opens separate choices for the national station, specialty music stations and state-based feeds.
- **Search by Location** opens National, capital-city, Other Locations and State tiles.
- **Music** opens a searchable list of music and audio genres, including Kids & Family and Soundscapes. A station can appear under more than one relevant genre. News and Sport have their own top-level destinations.
- **News and Talkback** and **Sport** open their matching station lists directly.
- **Community & Specialist** opens tiles for Community, Religion, Foreign Language, Country Music, Indigenous, Arts & Music, Radio Reading, Youth & Education, Seniors and LGBTQIA+ services. Established broadcasters such as SBS remain under their official network.
- **Not yet categorised** is always last and contains directory records that still require a confirmed network or specialist classification.
- **National** contains stations whose coverage is marked National in the directory.
- **Browse by location** opens the principal stations for each capital city. Sydney, Melbourne, Brisbane, Adelaide and Perth begin with **Top Rating Stations**, ordered by their supplied current ratings results, followed by all other stations for that city alphabetically. Other Locations opens the wider town and regional directory.
- **Browse by State** filters stations by their Australian state, territory or National coverage.
- The main **Search stations** field finds stations by name, network, location or other directory information. **Other Locations** also provides a local search field; the Networks page uses a direct tile list.
- Nova is organised into **Metro**, **Music**, **Talkback** and **MediaWorks New Zealand**. FIVEAA is listed under Talkback; MediaWorks' New Zealand services have their own tile.

Station lists include an alphabetical index for quick navigation. The final rows have extra scroll space so they can be brought fully above the mini-player. Favourites retains your chosen manual order.

The compact mini-player remains available at the bottom of Discover and every page opened from it, including Settings and Support. Tap it to return to the main player or use its Play/Pause control without leaving the current page.

Wireless downloads the published station directory and keeps its last complete copy for browsing when the directory service is temporarily unavailable. Stream playback still requires a suitable internet connection.

## The Player

The Playing pane keeps artwork large in portrait and places favourite shortcuts near the bottom. Favourite station names stay on one line. Audio output shares the controls row where space permits; narrow windows use a separate output row. Short windows and larger text can scroll, while wide landscape windows show artwork beside the controls.

The main player has three panes:

| Pane | Purpose |
|---|---|
| Playing | Station artwork, programme or song information, live-position bar, Play/Pause, audio controls, Sleep Timer and favourite shortcuts. |
| Details | Station description, contact links, location, state, frequency, region, network, genres, stream type and bitrate. Programme information appears here when the broadcaster supplies it. A station-specific report action covers playback, directory, artwork, ownership and legal concerns. |
| Sync | TV Sync on/off control, selected audio delay, half-second adjustment buttons and measured stream delay. |

The progress bar represents the current live position and buffering state. With TV Sync enabled, the captions show **TV Sync Enabled** and the measured stream delay. When reception is interrupted, Wireless attempts to reconnect automatically without requiring another press of Play.

Where a music stream or supported broadcaster now-playing service supplies reliable track metadata, Wireless shows **song title · artist** on the top row, with the **station name below**. The mini-player uses the same order. Album information, when supplied, remains available in the mini-player. CarPlay and other system playback surfaces use their third text line for the station name. Song information is also sent to the Lock Screen, Control Centre and connected vehicles. Triple M and Hit Metro and Regional broadcast stations use metadata embedded directly in their selected stream. Wireless also supports ABC music services, supported Triton StreamTheWorld feeds and official LiSTNR now-playing data for LiSTNR and SCA digital music stations. A brief gap is normal when a broadcaster reports that no current track is available. Track metadata is available only during normal playback with TV Sync off.

ABC Local Radio, Radio National, NewsRadio, Radio Australia and ABC sport feeds use ABC’s official programme schedules. When supplied, the current programme appears in Playing; Details shows its presenter, broadcast times and upcoming programmes. Schedules refresh automatically and follow the selected regional feed. Sport and event streams may have no programme listed between broadcasts, and some regional services may have gaps in ABC’s schedule data. Radio National’s Victorian and Tasmanian feeds use the national eastern schedule when ABC supplies no regional listings. Programme times describe the live broadcast and do not move with TV Sync delay. ABC music stations retain their song title and artist information.

Triple M and Hit embedded metadata remains authoritative. During some national networked programmes, a station may repeatedly supply an old technical playout marker rather than current song information. Wireless hides only exact `Asset Link`, `Asset Spot` and `Asset Stop` markers, records them in Stream Diagnostics, and clears any previous song rather than leaving it frozen on screen. It also prevents old timestamped values from replacing current information and clears metadata that remains unchanged beyond its freshness limit. Each SCA playback session uses a new stream request identifier so a previous session's playlist is not deliberately reused.

## Favourites

Tap the heart button on the player to add or remove the current station from Favourites. Wireless asks for confirmation before removing a station so an accidental tap does not change the list. The outlined heart in the top-right corner shows the number of saved stations and opens the complete Favourites list.

Use **Reorder** in Favourites to drag stations into your preferred order. The first two saved favourites other than the currently selected station appear as quick-play tiles at the bottom of the Playing pane. Tapping either tile starts that station immediately.

Favourites are stored on the device. iCloud synchronisation is not currently included.

## TV Sync

TV Sync delays live radio commentary so it can better match television pictures received through another service.

When TV Sync is off, the Sync pane shows only the **Sync audio to picture** tile. Turning it on reveals the **Saved audio delay** tile and its adjustment controls.

1. Open the **Sync** pane.
2. Turn on **Sync audio to picture**.
3. Choose a clear moment on the television, such as a ball being kicked or someone beginning to speak.
4. If you hear the commentary before you see the action, increase the delay. If you see the action first, decrease it.
5. Use the slider for larger changes or the minus and plus buttons for half-second adjustments until the sound matches the picture.

Wireless displays both your saved delay and the delay currently available from the active stream. Your chosen delay is remembered for the next time you use TV Sync. Playback remains controlled from the main Playing pane, not from the Sync pane.

When TV Sync is first turned on, Wireless may briefly show that it is building an audio buffer. The delay controls become available automatically when enough audio has been retained. This temporary preparation message does not mean the stream is incompatible.

Direct MP3 and AAC streams can be retained in Wireless's packet buffer. Compatible AAC HLS streams may use a seekable live window or a retained-packet fallback. Some HLS formats do not expose enough audio history for TV Sync; the Sync pane explains when the active stream cannot provide a seekable delay buffer.

HLS audio arrives in segments, so its measured delay can move in small steps. Wireless avoids repeated automatic HLS corrections that would introduce audible micro-stutters. If one stream variation performs poorly, open **Audio Controls** and try another available stream.

## Normal Live Playback and Stream Selection

Wireless begins preparing the selected station’s audio as soon as it opens in the player, including the last station restored at launch. This uses internet data before you press Play but produces no sound. Pressing Play reuses the prepared connection and buffer where available. Preparation stops after one minute without playback, when the app enters the background without playing, or when you press Pause. Startup speed still depends on reception and the broadcaster.

While playback is requested, Wireless keeps trying after a lost connection. It tries the station’s published stream alternatives and repeats in cycles, with waits increasing from one second to a maximum of 15 seconds between cycles. Press Pause to stop reconnection attempts. If iOS suspends the app during a prolonged background outage, reopen Wireless to let recovery continue.

With TV Sync off and Vocal Boost off, Wireless uses Apple's AVPlayer for stable live playback. It allows a short reliability buffer to build where appropriate and does not make TV-delay corrections.

Open **Audio Controls** to choose another stream offered by the station. Wireless remembers the selected stream variation for that station and restores it the next time the station is opened. Format and bitrate information appear in the Details pane when supplied by the directory.

Audio quality is determined by the broadcaster's stream. A higher bitrate can improve quality but may need a stronger connection. If a stream stops advancing, Wireless can reconnect or try another published stream for the same station.

## Vocal Boost

Vocal Boost can make speech easier to hear. Open **Audio Controls** and choose:

- **Off** — the original stream without speech processing.
- **Light** — gentle speech enhancement.
- **Standard** — stronger voice levelling and clarity.
- **Strong** — the most pronounced speech treatment.

Vocal Boost works with compatible direct MP3 and AAC streams. On iOS 27 or later, it also processes compatible HLS streams while retaining Apple’s live-stream playback. If native HLS processing is unavailable, Wireless can use an unencrypted AAC-segment fallback. Switching to that fallback may briefly reconnect playback. Other containers or protected streams continue without the effect. FairPlay-protected HLS cannot be processed. On iOS 26, choose a direct MP3 or AAC stream to use Vocal Boost.

Audio Controls shows whether Vocal Boost is ready, waiting for audio, active or unavailable. **Active** means audio has passed through speech processing; selecting a level alone does not mean the effect is running. If unavailable, the broadcast continues without the effect; try another stream. Listening Stats counts Vocal Boost only while processing is active.

Start with **Light** for broadcasts that are already heavily compressed. Standard and Strong can make speech more consistent, but may sound less natural on music or heavily processed broadcasts. Vocal Boost cannot restore detail lost in a low-bitrate source.

TV Sync and Vocal Boost cannot operate together; Vocal Boost is disabled while TV Sync is on.

## Sleep Timer

Tap the moon button on the Playing pane to open Sleep Timer. Choose a duration and Wireless will pause playback automatically when the timer expires. The sheet also opens **Sleep Schedule**, described below.

While a timer is active, reopen Sleep Timer to view the countdown, add five minutes or cancel it. Wireless gradually fades the volume during the final 30 seconds before pausing. Starting playback again after the timer has expired restores normal volume.

## Sleep Schedule

Sleep Schedule is a recurring, nightly sleep timer. Set it up once and it works every night, with no taps required at bedtime.

1. Tap the moon button on the Playing pane, then choose **Sleep Schedule** at the bottom of the Sleep Timer sheet.
2. Turn on the toggle and choose your **Active Hours**, for example 9:00 pm to 6:00 am. The window can cross midnight, and matching start and end times keep the schedule available all day.
3. Choose how often Wireless should check in: **10, 15, 20, 40 or 60 minutes** of playback.

Start playing a station during your active hours and the schedule arms itself. After the chosen duration, a soft chime plays over the station for up to a minute. Playback continues while the chime plays.

- **Still awake?** Tap **Still Listening** in the app or on the lock-screen notification (no need to unlock), or use Play/Pause on the Lock Screen, headphones or CarPlay. The station continues and the next check-in cycle starts.
- **Asleep?** Without a response, the station fades out over 30 seconds and pauses. Press Play in the morning to return to the live broadcast.
- **Active Hours ended?** Wireless dismisses any pending check-in and its notification. The station continues normally and Sleep Schedule does not ask again outside the selected window.

During your active hours, a bed icon appears beside the Discover button at the top of the player. While a station plays, it shows the minutes until the next check-in. Tap it to open Sleep Schedule.

Setting the regular Sleep Timer overrides the schedule for that listening session without changing the saved schedule. Turning Sleep Schedule off keeps your saved hours and interval for next time.

When you first turn Sleep Schedule on, Wireless asks for notification permission so the check-in can appear on the Lock Screen, including during Sleep Focus. If notifications are off, the chime still plays and Play/Pause or the in-app button still count as a response.

## Background Playback and System Controls

Wireless continues playing when the app moves to the background or the device is locked. The active playback engine and TV Sync position are retained across ordinary foreground and background changes.

The Lock Screen, Control Centre, headphone controls, AirPlay and compatible connected vehicles provide Play/Pause control and display station artwork. Song information is included when the active stream supplies acceptable metadata during normal playback.

Wireless pauses if an audio output such as wired headphones is disconnected. After a temporary loss of reception, playback attempts to resume automatically when connectivity returns. A deliberate manual Pause is respected.

When Stream Diagnostics is enabled, its Metadata view records every metadata result received from the stream and supported companion services. Use the **Metadata**, **Playback** and **All** selector to change the visible records; Wireless remembers that selection. Dedicated raw fields preserve the broadcaster's exact title, artist and album text without trimming or normalising it; control characters are escaped only to keep each log entry parseable. Each result also records its display-ready interpretation, classification, whether it repeated or changed, and the exact display decision. Advertisements, programme labels and technical markers remain visible in the diagnostic record even when they are hidden from the player. Provider records include the station name, service identifier, transport, response details and why a source was enabled or unavailable. For Triple M and Hit broadcast stations, the provider decision records that embedded stream metadata is authoritative. Heartbeats separately report the ages of the last provider contact, distinct candidate, usable song receipt and genuine track change. Rejected technical markers and stale candidates do not reset the usable-song timer. `metadata.silence` identifies a period with no usable song metadata, while `metadata.sourceSilence` identifies an inactive secondary source. `metadata.stale` records the first and last sighting, repeat count, embedded timestamp age, display age and reason whenever an old or unchanged value is suppressed or cleared. Authentication values and device names remain excluded from exported logs.

## CarPlay

Open Wireless in CarPlay to control the same player as your iPhone. CarPlay opens on the player once a station has been chosen, or on Favourites before then.

The CarPlay player shows the song title, artist and station name when current song information is available. At other times it shows the station name, network and location or frequency, instead of repeating the station name.

- Choose **Favourites** in the top-right corner of the player to open your saved stations.
- Favourites also lists your recently played stations. Choose **Discover** in the top-right corner of Favourites to browse Networks, Locations, Music, News and Talkback, Sport, and Community & Specialist stations.
- Choose a station to start playing it and return to the player.
- Use the heart button on the player to add or remove the current station from Favourites.

Favourites changed in CarPlay also update on your iPhone. Auto Resume applies when Wireless starts from CarPlay.

## Listening Stats

Open **Settings > Listening Stats** to see how you use Wireless. Tracking begins when this version is installed. Wireless cannot reconstruct earlier listening time from Favourites or Recently Played because those records do not prove how long audio was heard.

Choose **7 Days**, the displayed month, the displayed year or **Lifetime**. The glass period tabs are centred above the statistics. At larger text sizes or in narrow windows, swipe the tabs horizontally if needed. When an earlier completed period contains listening, a **This / Last** control compares the current and previous week, month or year.

| Section | Meaning |
|---|---|
| Time listened | Audio confirmed as rendered by the active playback engine. Connecting, buffering, TV Sync delay insertion and reconnection time do not count. |
| Top Stations | Stations ranked by listening time. Expand a station for average and longest session, listening share and last-listened detail. |
| Listening Heatmap | Daily listening for the selected week or month. |
| Listening Over Time | Monthly listening for the selected year or Lifetime. |
| Listening Clock | The hours of day when you listen most. |
| How You Listen | Average and longest sessions, plus listening by Live, TV Sync, Vocal Boost and audio-route category. |

A listening session begins when a station first renders audio and ends when you pause or change station. A brief reconnection or alternate-stream failover for the same station remains one session, but the silent gap is excluded.

Use the options button on Listening Stats to export an importable JSON backup or a CSV spreadsheet, or to import a previous JSON backup. **Stats Health** shows the number of recorded days, the tracking start, the last local save and recovery state.

Listening Stats are protected in Wireless’s local Application Support storage and are never sent to Wireless. They do not currently synchronise through iCloud.

## Listening History

Open **Settings > Listening History** to see individual live-radio sessions, newest first. A session appears after Wireless confirms at least one minute of rendered audio.

Sessions are grouped under **Today**, **Yesterday** or their calendar date. Search by station, network or location. Each row shows the listening duration and start and finish times; the active session is highlighted as **Playing**.

Tap a current directory station or swipe from the leading edge to play it. Swipe from the trailing edge to add or remove it from Favourites. If a retained station is no longer available in the directory, its history remains readable but playback and favourite actions are unavailable.

Pausing and later resuming the same station creates a new row. Buffering and reconnection gaps do not create another row and do not add listening time. A session crossing midnight remains one history row, while Listening Stats still assigns rendered audio to the correct day and hour.

Listening History uses the same protected local data as Listening Stats and is included in its JSON backup. Wireless retains the newest 5,000 detailed sessions without reducing the longer-term daily totals used by Listening Stats.

## Settings

Open the gear button in the top-right corner of Discover to reach Settings.

| Setting | Behaviour |
|---|---|
| Auto Resume | Starts the last selected station once whenever Wireless is freshly launched. Off by default. It does not restart playback merely because the app moves between the foreground and background. |
| Keep Screen Awake | Prevents the display from dimming while audio is playing on the full-screen player. Off by default. |
| Share TestFlight link with your friends | Opens the system share sheet with the current Wireless TestFlight invitation. |

Settings also provides this Support guide and the installed app version. Under **About**, **View Source on GitHub** opens [Wireless’s public repository](https://github.com/kevinvperry/Wireless), and **MIT Licence** opens the [licence text](https://github.com/kevinvperry/Wireless/blob/main/LICENSE). Wireless’s original code and documentation use the MIT Licence. Vocal Boost retains MPL-2.0; **Open Source Acknowledgements** explains the applicable licences and credits.

## Contact and station reports

Open **Settings > Contact Wireless** to ask a question, report a general problem or raise a legal concern directly with the Wireless developer.

For a concern about a particular station, open that station’s **Details** pane and choose **Report an issue with this station**. Include the station name and the relevant technical, directory, ownership or legal concern in the form. Reports can cover:

- Playback or stream failures.
- Incorrect station, network, location or contact information.
- Artwork, trademark or branding concerns.
- Station ownership, inclusion, removal or other legal requests.

Broadcasters and rights holders can use the same station-report action to request a correction, replacement stream or removal from the Wireless directory.

## Troubleshooting

### A station will not play

- Confirm the device has an internet connection.
- Open Audio Controls and try another available stream.
- Pause and press Play again to start a fresh connection.
- Try another station to determine whether the issue is limited to one broadcaster.

### Playback pauses or stutters

- Turn TV Sync off to return to normal AVPlayer playback.
- Try a direct MP3 or AAC stream if the station offers one.
- Select a lower-bitrate stream when reception is weak.
- Disable Vocal Boost to return compatible streams to the standard playback backend.

### TV Sync is unavailable or unstable

- Check the Sync pane for a compatibility message.
- Try another stream variation in Audio Controls.
- Prefer direct MP3 or AAC when the broadcaster provides it.
- Increase the selected delay if the connection cannot retain enough audio consistently.

### Station information is missing

Station descriptions, contact details, artwork, programme guides and song metadata depend on information supplied by the directory or broadcaster. Missing information does not prevent playback. Directory corrections and artwork updates can appear without requiring a new app version after the app refreshes its station data.
