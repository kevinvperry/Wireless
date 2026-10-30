import Foundation

extension StationPlaybackIntent {
    @MainActor func controlPlayback() async {
        let player = MobilePlayer.shared
        // Resolve stable identity against live app state, never a widget-supplied URL.
        let station = player.library.stations.first { $0.id == stationID }
            ?? player.library.favourites.first { $0.id == stationID }
            ?? (player.station.id == stationID ? player.station : nil)
        guard let station, !station.playableStreams.isEmpty else { return }
        if shouldPlay {
            if player.station.id != station.id { player.playStation(station) }
            else if !player.requested { player.toggle() }
        } else if player.station.id == station.id, player.requested {
            player.toggle()
        }
        player.publishWidgetSnapshot()
    }
}
