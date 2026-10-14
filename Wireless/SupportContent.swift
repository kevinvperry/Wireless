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
        vocalBoost, sleepTimer, systemPlayback, settings, troubleshooting
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
        summary: "Browse networks, cities, states and National radio",
        blocks: [
            .paragraph("Discover provides several ways to browse the station directory:"),
            .table([
                ["Networks", "Groups stations by broadcaster."],
                ["National", "Stations whose directory coverage is marked National."],
                ["Browse by location", "Capital-city stations are prioritised. Other Locations opens the wider town and regional directory."],
                ["Browse by State", "Filters by Australian state, territory or National coverage."],
                ["Search", "Finds stations by name, network, location or other directory information."]
            ]),
            .callout(.tip, "Wireless keeps the last complete directory for browsing if the directory service is temporarily unavailable. Stream playback still requires a suitable internet connection.")
        ]
    )

    private static let player = WirelessSupportSection(
        id: "player", icon: "play.circle.fill", title: "The Player",
        summary: "Playing, Details and Sync panes",
        blocks: [
            .table([
                ["Playing", "Artwork, programme or song information, live-position bar, Play/Pause, audio controls, Sleep Timer and favourite shortcuts."],
                ["Details", "Station description, contact links, location, state, genres, stream type and bitrate. Programme information appears when available."],
                ["Sync", "TV Sync on/off, selected delay, half-second controls and measured stream delay."]
            ]),
            .paragraph("The progress bar represents live position and buffering. With TV Sync enabled, its captions show **Sync Enabled** and the measured stream delay. Wireless attempts to reconnect automatically after reception is interrupted."),
            .heading("Song and programme information"),
            .paragraph("When a music stream supplies reliable metadata, Wireless can show song title, artist and album beneath the station name and publish it to system playback surfaces. Track metadata is available only during normal playback with TV Sync off. Station information remains visible when no suitable track metadata is available.")
        ]
    )

    private static let favourites = WirelessSupportSection(
        id: "favourites", icon: "heart", title: "Favourites",
        summary: "Save, reorder and quickly play your preferred stations",
        blocks: [
            .paragraph("Tap the heart button on the player to add or remove the current station. The outlined heart in the top-right corner shows the number saved and opens the full Favourites list."),
            .paragraph("Use **Reorder** to drag stations into your preferred order. The first two favourites other than the current station appear as quick-play tiles at the bottom of Playing."),
            .callout(.note, "Favourites are stored on the device. iCloud synchronisation is not currently included.")
        ]
    )

    private static let sync = WirelessSupportSection(
        id: "tv-sync", icon: "dot.radiowaves.left.and.right", title: "TV Sync",
        summary: "Delay radio commentary to match television pictures",
        blocks: [
            .steps([
                "Open the **Sync** pane.",
                "Turn on **Sync audio to picture**.",
                "Use the slider for larger changes or the minus and plus buttons for half-second adjustments.",
                "Compare commentary with the television picture and continue adjusting until they align."
            ]),
            .paragraph("Wireless shows the selected delay and the measured delay available from the active stream. The selected delay is saved."),
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
            ])
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
