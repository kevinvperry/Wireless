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

- **Networks** groups stations by broadcaster.
- **National** contains stations whose coverage is marked National in the directory.
- **Browse by location** prioritises the principal stations for each capital city. Other Locations opens the wider town and regional directory.
- **Browse by State** filters stations by their Australian state, territory or National coverage.
- **Search** finds stations by name, network, location or other directory information.

Wireless downloads the published station directory and keeps its last complete copy for browsing when the directory service is temporarily unavailable. Stream playback still requires a suitable internet connection.

## The Player

The main player has three panes:

| Pane | Purpose |
|---|---|
| Playing | Station artwork, programme or song information, live-position bar, Play/Pause, audio controls, Sleep Timer and favourite shortcuts. |
| Details | Station description, contact links, location, state, genres, stream type and bitrate. Programme information appears here when the broadcaster supplies it. |
| Sync | TV Sync on/off control, selected audio delay, half-second adjustment buttons and measured stream delay. |

The progress bar represents the current live position and buffering state. With TV Sync enabled, the captions show **Sync Enabled** and the measured stream delay. When reception is interrupted, Wireless attempts to reconnect automatically without requiring another press of Play.

Where a music stream supplies reliable track metadata, Wireless can show the song title, artist and album beneath the station name. This metadata is also sent to the Lock Screen, Control Centre and connected vehicles. Track metadata is available only during normal playback with TV Sync off. Wireless continues showing station information when no suitable track metadata is available.

## Favourites

Tap the heart button on the player to add or remove the current station from Favourites. The outlined heart in the top-right corner shows the number of saved stations and opens the complete Favourites list.

Use **Reorder** in Favourites to drag stations into your preferred order. The first two saved favourites other than the currently selected station appear as quick-play tiles at the bottom of the Playing pane. Tapping either tile starts that station immediately.

Favourites are stored on the device. iCloud synchronisation is not currently included.

## TV Sync

TV Sync delays live radio commentary so it can better match television pictures received through another service.

1. Open the **Sync** pane.
2. Turn on **Sync audio to picture**.
3. Use the slider for larger changes or the minus and plus buttons for half-second adjustments.
4. Compare the commentary with the television picture and continue adjusting until they align.

Wireless displays both the selected delay and the measured delay available from the active stream. The selected delay is saved for future listening.

Direct MP3 and AAC streams can be retained in Wireless's packet buffer. Compatible AAC HLS streams may use a seekable live window or a retained-packet fallback. Some HLS formats do not expose enough audio history for TV Sync; the Sync pane explains when the active stream cannot provide a seekable delay buffer.

HLS audio arrives in segments, so its measured delay can move in small steps. Wireless avoids repeated automatic HLS corrections that would introduce audible micro-stutters. If one stream variation performs poorly, open **Audio Controls** and try another available stream.

## Normal Live Playback and Stream Selection

With TV Sync off and Vocal Boost off, Wireless uses Apple's AVPlayer for stable live playback. It allows a short reliability buffer to build where appropriate and does not make TV-delay corrections.

Open **Audio Controls** to choose another stream offered by the station. Wireless remembers the selected stream variation for that station and restores it the next time the station is opened. Format and bitrate information appear in the Details pane when supplied by the directory.

Audio quality is determined by the broadcaster's stream. A higher bitrate can improve quality but may need a stronger connection. If a stream stops advancing, Wireless can reconnect or try another published stream for the same station.

## Vocal Boost

Vocal Boost can make speech easier to hear. Open **Audio Controls** and choose:

- **Off** — the original stream without speech processing.
- **Light** — gentle speech enhancement.
- **Standard** — stronger voice levelling and clarity.
- **Strong** — the most pronounced speech treatment.

Vocal Boost is available for compatible direct MP3 and AAC streams. Enabling it switches playback to Wireless's enhanced audio engine. TV Sync and Vocal Boost cannot operate together; Vocal Boost is disabled while TV Sync is on.

## Sleep Timer

Tap the moon button on the Playing pane to open Sleep Timer. Choose a duration and Wireless will pause playback automatically when the timer expires.

While a timer is active, reopen Sleep Timer to view the countdown, add five minutes or cancel it. Wireless gradually fades the volume during the final 30 seconds before pausing. Starting playback again after the timer has expired restores normal volume.

## Background Playback and System Controls

Wireless continues playing when the app moves to the background or the device is locked. The active playback engine and TV Sync position are retained across ordinary foreground and background changes.

The Lock Screen, Control Centre, headphone controls, AirPlay and compatible connected vehicles provide Play/Pause control and display station artwork. Song information is included when the active stream supplies acceptable metadata during normal playback.

Wireless pauses if an audio output such as wired headphones is disconnected. After a temporary loss of reception, playback attempts to resume automatically when connectivity returns. A deliberate manual Pause is respected.

## Settings

Open the gear button in the top-right corner of Discover to reach Settings.

| Setting | Behaviour |
|---|---|
| Auto Resume | Starts the last selected station once whenever Wireless is freshly launched. Off by default. It does not restart playback merely because the app moves between the foreground and background. |
| Keep Screen Awake | Prevents the display from dimming while audio is playing on the full-screen player. Off by default. |
| Share TestFlight link with your friends | Opens the system share sheet with the current Wireless TestFlight invitation. |

Settings also provides this Support guide and the installed app version. Under **About**, **View Source on GitHub** opens [Wireless’s public repository](https://github.com/kevinvperry/Wireless), and **MIT Licence** opens the [licence text](https://github.com/kevinvperry/Wireless/blob/main/LICENSE). Wireless’s original code and documentation use the MIT Licence. Vocal Boost retains MPL-2.0; **Open Source Acknowledgements** explains the applicable licences and credits.

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
