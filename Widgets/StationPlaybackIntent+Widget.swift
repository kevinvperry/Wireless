// Adapted from Autohop: compile witness only; the app owns audio playback.
extension StationPlaybackIntent {
    @MainActor func controlPlayback() async {}
}
