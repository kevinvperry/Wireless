import SwiftUI

// This in-app content mirrors SUPPORT_GUIDE.md. Update both together.
enum WirelessSupportCalloutStyle {
    case tip, note, warning

    var symbol: String {
        switch self {
        case .tip: "lightbulb.fill"
        case .note: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .tip: .purple
        case .note: Color(red: 0.36, green: 0.60, blue: 1)
        case .warning: Color(red: 0.96, green: 0.55, blue: 0.26)
        }
    }
}

enum WirelessSupportBlock {
    case paragraph(String)
    case heading(String)
    case bullets([String])
    case steps([String])
    case callout(WirelessSupportCalloutStyle, String)
    case table([[String]])
}

struct WirelessSupportSection: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let blocks: [WirelessSupportBlock]
}

enum WirelessSupportGuide {
    static let sections: [WirelessSupportSection] = [
        gettingStarted, discover, player, favourites, sync, streams,
        vocalBoost, sleepTimer, sleepSchedule, systemPlayback, carPlay, listeningStats, settings, contact, troubleshooting
    ]

    private static let gettingStarted = WirelessSupportSection(
        id: "getting-started", icon: "sparkles", title: "Getting Started",
        summary: "Find a station, start listening and save favourites",
        blocks: [
            .paragraph("Wireless lets you discover Australian radio stations, save favourites and return quickly to the stations you listen to most."),
            .steps([
                "Open **Discover** from the player.",
                "Browse a capital city, network, National stations, another location or a state and territory.",
                "Tap a station to select it and begin playback.",
                "Tap the heart button to save the station to **Favourites**."
            ]),
            .callout(.note, "On a first installation with no saved station, Wireless opens Discover. Later launches restore the last selected station without starting audio unless **Auto Resume** is enabled.")
        ]
    )

    private static let discover = WirelessSupportSection(
        id: "discover", icon: "dot.radiowaves.left.and.right", title: "Discovering Stations",
        summary: "Browse music genres, networks, cities, states and National radio",
        blocks: [
            .paragraph("Discover provides several ways to browse the station directory:"),
            .table([
                ["Search by Network", "Shows major broadcasters alphabetically in a grid using the network artwork maintained in the Wireless directory. All Networks then lists every network, including the featured broadcasters, alphabetically. ACE Radio Network appears as ACE Radio, ARN as ARN Regional and Hit Network as Hit. Networks with distinct services offer sub-network tiles."],
                ["Search by Location", "Opens National, capital-city, Other Locations and State tiles."],
                ["Music", "Opens searchable music and audio genres, including Kids & Family and Soundscapes. A station can appear under more than one relevant genre. News and Sport have their own top-level destinations."],
                ["News and Talkback", "Opens news, current affairs and talk stations directly."],
                ["Sport", "Opens sport commentary, analysis and racing stations directly."],
                ["Community & Specialist", "Opens Community, Religion, Foreign Language, Country Music, Indigenous, Arts & Music, Radio Reading, Youth & Education, Seniors and LGBTQIA+ tiles."],
                ["National", "Stations whose directory coverage is marked National."],
                ["Browse by location", "Opens capital-city stations. Sydney, Melbourne, Brisbane, Adelaide and Perth begin with Top Rating Stations in current ratings order, followed by all other stations for that city alphabetically. Other Locations opens the wider town and regional directory."],
                ["Browse by State", "Filters by Australian state, territory or National coverage."],
                ["Search", "The main station search finds stations by name, network and location. Other Locations also has a local search field; Networks uses a direct tile list."]
            ]),
            .paragraph("Station lists include an alphabetical index for quick navigation. Favourites retains your chosen manual order. The mini-player remains available at the bottom of Discover and every page opened from it, including Settings and Support. Lists include enough scroll space to bring their final rows fully above it. Tap it to return to Playing or use Play/Pause without leaving the current page."),
            .callout(.tip, "Wireless keeps the last complete directory for browsing if the directory service is temporarily unavailable. Stream playback still requires a suitable internet connection.")
        ]
    )

    private static let player = WirelessSupportSection(
        id: "player", icon: "play.circle.fill", title: "The Player",
        summary: "Playing, Details and Sync panes",
        blocks: [
            .table([
                ["Playing", "Artwork, programme or song information, live-position bar, Play/Pause, audio controls, Sleep Timer and favourite shortcuts."],
                ["Details", "Station description, contact links, location, state, frequency, region, network, genres, stream type and bitrate. Programme information appears when available."],
                ["Sync", "TV Sync on/off, selected delay, half-second controls and measured stream delay."]
            ]),
            .paragraph("The progress bar represents live position and buffering. With TV Sync enabled, its captions show **TV Sync Enabled** and the measured stream delay. Wireless attempts to reconnect automatically after reception is interrupted."),
            .heading("Song and programme information"),
            .paragraph("When a music stream or supported broadcaster now-playing service supplies reliable metadata, Wireless shows **song title · artist** on the top row and the **station name below**, including in the mini-player. Album information remains available in the mini-player when supplied. CarPlay and other system playback surfaces use their third text line for the station name. Triple M and Hit Metro and Regional broadcast stations use metadata embedded directly in their selected stream. Wireless also supports ABC music services, supported Triton StreamTheWorld feeds and official LiSTNR now-playing data for LiSTNR and SCA digital music stations. A brief gap is normal when a broadcaster reports that no current track is available. Track metadata is available only during normal playback with TV Sync off."),
            .paragraph("Triple M and Hit embedded metadata remains authoritative. During some national networked programmes, a station may repeatedly supply an old technical playout marker rather than current song information. Wireless hides only exact Asset Link, Asset Spot and Asset Stop markers, records them in Stream Diagnostics, and clears any previous song rather than leaving it frozen on screen. It also prevents old timestamped values from replacing current information and clears metadata that remains unchanged beyond its freshness limit. Each SCA playback session uses a new stream request identifier so a previous session's playlist is not deliberately reused.")
        ]
    )

    private static let favourites = WirelessSupportSection(
        id: "favourites", icon: "heart", title: "Favourites",
        summary: "Save, reorder and quickly play your preferred stations",
        blocks: [
            .paragraph("Tap the heart button on the player to add or remove the current station. Wireless asks for confirmation before removing a station. The outlined heart in the top-right corner shows the number saved and opens the full Favourites list."),
            .paragraph("Use **Reorder** to drag stations into your preferred order. The first two favourites other than the current station appear as quick-play tiles at the bottom of Playing."),
            .callout(.note, "Favourites are stored on the device. iCloud synchronisation is not currently included.")
        ]
    )

    private static let sync = WirelessSupportSection(
        id: "tv-sync", icon: "dot.radiowaves.left.and.right", title: "TV Sync",
        summary: "Delay radio commentary to match television pictures",
        blocks: [
            .paragraph("TV pictures can arrive a few seconds after live radio. TV Sync holds the radio back so the commentary and picture happen together. When TV Sync is off, the Sync pane shows only the **Sync audio to picture** tile. Turning it on reveals the **Saved audio delay** controls."),
            .steps([
                "Open the **Sync** pane.",
                "Turn on **Sync audio to picture**.",
                "Choose a clear moment, such as a ball being kicked or someone beginning to speak.",
                "If you hear the commentary before you see the action, increase the delay. If you see the action first, decrease it.",
                "Use the slider for larger changes or the minus and plus buttons for half-second adjustments until the sound matches the picture."
            ]),
            .paragraph("Wireless shows your saved delay and the delay available from the active stream. Your chosen delay is remembered. Playback remains controlled from the main Playing pane."),
            .paragraph("When TV Sync is first turned on, Wireless may briefly show that it is building an audio buffer. The controls become available automatically when enough audio has been retained. This does not mean the stream is incompatible."),
            .paragraph("Direct MP3 and AAC streams can be retained in Wireless's packet buffer. Compatible AAC HLS may use a seekable live window or retained-packet fallback. Some HLS formats do not expose enough audio history for Sync."),
            .callout(.warning, "HLS arrives in segments, so measured delay can move in small steps. Wireless avoids repeated HLS corrections that would cause micro-stutters. If performance is poor, try another stream in **Audio Controls**.")
        ]
    )

    private static let streams = WirelessSupportSection(
        id: "streams", icon: "waveform", title: "Live Playback and Streams",
        summary: "Choose a stream and understand quality and reliability",
        blocks: [
            .paragraph("With TV Sync and Vocal Boost off, Wireless uses Apple's AVPlayer for stable live playback. It allows a short reliability buffer where appropriate and does not make TV-delay corrections."),
            .paragraph("Open **Audio Controls** to select another published stream. Wireless remembers the choice for that station. Format and bitrate appear in Details when the directory supplies them."),
            .bullets([
                "A higher bitrate can improve quality but may require a stronger connection.",
                "If a stream stops advancing, Wireless can reconnect or try another published stream.",
                "Audio quality is ultimately determined by the broadcaster's stream."
            ])
        ]
    )

    private static let vocalBoost = WirelessSupportSection(
        id: "vocal-boost", icon: "slider.horizontal.3", title: "Vocal Boost",
        summary: "Improve speech clarity on compatible direct streams",
        blocks: [
            .table([
                ["Off", "Original stream without speech processing."],
                ["Light", "Gentle speech enhancement."],
                ["Standard", "Stronger voice levelling and clarity."],
                ["Strong", "The most pronounced speech treatment."]
            ]),
            .paragraph("Vocal Boost works with compatible direct MP3 and AAC streams and switches playback to Wireless's enhanced audio engine."),
            .callout(.note, "TV Sync and Vocal Boost cannot operate together. Vocal Boost is disabled while TV Sync is on.")
        ]
    )

    private static let sleepTimer = WirelessSupportSection(
        id: "sleep-timer", icon: "moon.zzz", title: "Sleep Timer",
        summary: "Pause playback automatically after a chosen duration",
        blocks: [
            .paragraph("Tap the moon button on Playing and choose a duration. Wireless pauses automatically when the timer expires."),
            .paragraph("Reopen Sleep Timer to view the countdown, add five minutes or cancel it. Volume fades during the final 30 seconds. Starting playback after expiry restores normal volume.")
        ]
    )

    // Adapted from Autohop's Sleep Schedule support section for live radio.
    private static let sleepSchedule = WirelessSupportSection(
        id: "sleep-schedule", icon: "bed.double.fill", title: "Sleep Schedule",
        summary: "A recurring nightly timer that checks if you're awake",
        blocks: [
            .paragraph("Sleep Schedule is a **recurring, nightly sleep timer** — set it up once and it works every night, with no taps required at bedtime."),
            .heading("Setting it up"),
            .steps([
                "Tap the moon button on Playing, then choose **Sleep Schedule** at the bottom of the Sleep Timer sheet.",
                "Turn on the toggle and choose your **Active Hours** — for example 9:00 pm to 6:00 am. The window can cross midnight, and matching start and end times keep it available all day.",
                "Choose how often Wireless should check in: **10, 15, 20, 40 or 60 minutes** of playback."
            ]),
            .paragraph("During your active hours, a **bed icon** appears beside the Discover button at the top of the player. While a station plays, it shows the minutes until the next check-in. Tap it to open Sleep Schedule."),
            .heading("How a night works"),
            .paragraph("Start playing a station during your active hours and the schedule arms itself. After the chosen duration, a **soft, meditative chime** plays over the station — playback doesn't stop — asking, in effect, \"are you still listening?\""),
            .bullets([
                "**Still awake?** Tap **Still Listening** in the app or on the lock-screen notification (no need to unlock your phone), or use Play/Pause on the Lock Screen, your headphones or CarPlay. The station continues and the cycle restarts.",
                "**Asleep?** If you don't respond within a minute, the station fades out over 30 seconds and pauses. Press Play in the morning to return to the live broadcast.",
                "**Active Hours ended?** Wireless dismisses any pending check-in and its notification. Your station continues normally, but Sleep Schedule will not ask again outside the selected window."
            ]),
            .callout(.tip, "**Tip:** Setting the regular Sleep Timer overrides the schedule for that listening session — handy for nights when you want a fixed cutoff instead of check-ins."),
            .callout(.note, "When you first turn Sleep Schedule on, Wireless asks for notification permission so the check-in can appear on the Lock Screen. If notifications are off, the chime still plays and Play/Pause or the in-app button still count as a response.")
        ]
    )

    private static let systemPlayback = WirelessSupportSection(
        id: "background", icon: "lock.iphone", title: "Background and System Controls",
        summary: "Lock Screen, Control Centre, AirPlay and reconnection",
        blocks: [
            .paragraph("Wireless continues playing in the background and while the device is locked. Ordinary foreground/background changes retain the active playback engine and TV Sync position."),
            .paragraph("The Lock Screen, Control Centre, headphone controls, AirPlay and compatible connected vehicles provide Play/Pause and station artwork. Song information is included when supplied during normal playback."),
            .bullets([
                "Wireless pauses if an audio output such as wired headphones is disconnected.",
                "Playback attempts to resume after temporary reception loss.",
                "A deliberate manual Pause is respected."
            ]),
            .paragraph("When Stream Diagnostics is enabled, its Metadata view records every metadata result received from the stream and supported companion services. Use the **Metadata**, **Playback** and **All** selector to change the visible records; Wireless remembers that selection. Dedicated raw fields preserve the broadcaster's exact title, artist and album text without trimming or normalising it; control characters are escaped only to keep each log entry parseable. Each result also records its display-ready interpretation, classification, whether it repeated or changed, and the exact display decision. Advertisements, programme labels and technical markers remain visible in the diagnostic record even when they are hidden from the player. Provider records include the station name, service identifier, transport, response details and why a source was enabled or unavailable. For Triple M and Hit broadcast stations, the provider decision records that embedded stream metadata is authoritative. Heartbeats separately report provider contact, the last distinct candidate, the last usable song receipt and the last genuine track change. Rejected technical markers and stale candidates do not reset the usable-song timer. metadata.silence identifies a period with no usable song metadata, metadata.sourceSilence identifies an inactive secondary source, and metadata.stale records the first and last sighting, repeat count, embedded timestamp age, display age and reason whenever an old or unchanged value is suppressed or cleared. Authentication values and device names remain excluded from exported logs.")
        ]
    )

    private static let carPlay = WirelessSupportSection(
        id: "carplay", icon: "car.fill", title: "CarPlay",
        summary: "The player, Favourites and Discover in the car",
        blocks: [
            .paragraph("Open Wireless in CarPlay to control the same player as your iPhone. CarPlay opens on the player once a station has been chosen, or on Favourites before then."),
            .paragraph("The CarPlay player shows the song title, artist and station name when current song information is available. At other times it shows the station name, network and location or frequency, instead of repeating the station name."),
            .bullets([
                "Choose Favourites in the top-right corner of the player to open your saved stations.",
                "Favourites also lists your recently played stations. Choose Discover in the top-right corner of Favourites to browse Networks, Locations, Music, News and Talkback, Sport, and Community & Specialist stations.",
                "Choose a station to start playing it and return to the player.",
                "Use the heart button on the player to add or remove the current station from Favourites."
            ]),
            .paragraph("Favourites changed in CarPlay also update on your iPhone. Auto Resume applies when Wireless starts from CarPlay.")
        ]
    )

    private static let settings = WirelessSupportSection(
        id: "settings", icon: "gearshape", title: "Settings",
        summary: "Auto Resume, screen behaviour and sharing Wireless",
        blocks: [
            .paragraph("Open the gear button in the top-right corner of Discover."),
            .table([
                ["Auto Resume", "Starts the last station once on a fresh launch. Off by default. Foreground/background changes do not trigger it."],
                ["Keep Screen Awake", "Stops dimming while audio plays on the full-screen player. Off by default."],
                ["Share TestFlight link", "Opens the system share sheet with the Wireless TestFlight invitation."]
            ]),
            .paragraph("Settings also provides this guide and the installed app version. The About section links to Wireless’s public GitHub repository and MIT Licence. Wireless’s original code and documentation use the MIT Licence; Vocal Boost retains MPL-2.0, with details in Open Source Acknowledgements.")
        ]
    )

    private static let listeningStats = WirelessSupportSection(
        id: "listening-stats", icon: "chart.bar.xaxis", title: "Listening Stats",
        summary: "Listening time, top stations and your radio habits",
        blocks: [
            .paragraph("Open **Settings > Listening Stats**. Wireless begins tracking when this version is installed; Favourites and Recently Played cannot be used to reconstruct earlier listening time."),
            .paragraph("Choose **7 Days**, the displayed month, the displayed year or **Lifetime**. When an earlier completed period contains listening, use the **This / Last** control to compare it."),
            .table([
                ["Time listened", "Audio confirmed as rendered by the active playback engine. Connecting, buffering, delay insertion and reconnection time do not count."],
                ["Top Stations", "Stations ranked by listening time, with session length, listening share and last-listened detail."],
                ["Listening Heatmap", "Daily listening for the selected week or month."],
                ["Listening Over Time", "Monthly listening for the selected year or Lifetime."],
                ["Listening Clock", "The hours of day when you listen most."],
                ["How You Listen", "Average and longest sessions, plus listening by Live, TV Sync, Vocal Boost and audio-route category."]
            ]),
            .paragraph("A listening session begins when a station first renders audio and ends when you pause or change station. A brief reconnection or alternate-stream failover for the same station remains one session, but the silent gap is excluded."),
            .paragraph("Use the options button on Listening Stats to export an importable JSON backup or a CSV spreadsheet, or to import a previous JSON backup. Stats Health shows recorded days, the tracking start, the last local save and recovery state."),
            .callout(.note, "Listening Stats are protected in Wireless’s local Application Support storage and are never sent to Wireless. They do not currently synchronise through iCloud.")
        ]
    )

    private static let contact = WirelessSupportSection(
        id: "contact", icon: "envelope", title: "Contact and Station Reports",
        summary: "Report technical, directory, ownership or legal concerns",
        blocks: [
            .paragraph("Open **Settings > Contact Wireless** to ask a question, report a general problem or raise a legal concern directly with the Wireless developer."),
            .paragraph("For a concern about a particular station, open that station’s **Details** pane and choose **Report an issue with this station**. Include the station name and the relevant technical, directory, ownership or legal concern in the form."),
            .bullets([
                "Playback or stream failures",
                "Incorrect station, network, location or contact information",
                "Artwork, trademark or branding concerns",
                "Station ownership, inclusion, removal or other legal requests"
            ]),
            .callout(.note, "Broadcasters and rights holders can use the same station-report action to request a correction, replacement stream or removal from the Wireless directory.")
        ]
    )

    private static let troubleshooting = WirelessSupportSection(
        id: "troubleshooting", icon: "wrench.and.screwdriver", title: "Troubleshooting",
        summary: "Steps for playback, reception and TV Sync problems",
        blocks: [
            .heading("A station will not play"),
            .bullets(["Confirm the device is online.", "Try another stream in Audio Controls.", "Pause and press Play again.", "Try another station to identify a broadcaster-specific problem."]),
            .heading("Playback pauses or stutters"),
            .bullets(["Turn TV Sync off for normal AVPlayer playback.", "Try direct MP3 or AAC.", "Choose a lower bitrate in weak reception.", "Disable Vocal Boost to return to standard playback."]),
            .heading("TV Sync is unavailable or unstable"),
            .bullets(["Read the compatibility message in Sync.", "Try another stream variation.", "Prefer direct MP3 or AAC.", "Increase the delay if the connection cannot retain enough audio consistently."]),
            .heading("Station information is missing"),
            .paragraph("Descriptions, contacts, artwork, programme guides and song metadata depend on directory or broadcaster data. Missing information does not prevent playback. Directory corrections can appear after a data refresh without a new app version.")
        ]
    )
}
