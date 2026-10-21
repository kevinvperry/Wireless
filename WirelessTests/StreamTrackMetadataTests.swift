import XCTest
import AVFoundation

final class StreamTrackMetadataTests: XCTestCase {
    func testCarPlayNowPlayingUsesStationContextWhenTrackMetadataIsAbsent() {
        let text = NowPlayingTextProjection.make(
            stationName: "Triple M Melbourne 105.1",
            network: "Triple M",
            location: "Melbourne",
            frequency: "105.1 FM",
            track: nil
        )

        XCTAssertEqual(text.title, "Triple M Melbourne 105.1")
        XCTAssertEqual(text.artist, "Triple M")
        XCTAssertEqual(text.album, "Melbourne · 105.1 FM")
    }

    func testCarPlayNowPlayingAlwaysUsesStationNameWithTrackMetadata() {
        let text = NowPlayingTextProjection.make(
            stationName: "Triple M Melbourne 105.1",
            network: "Triple M",
            location: "Melbourne",
            frequency: "105.1 FM",
            track: StreamTrackMetadata(
                title: "The Boys Light Up",
                artist: "Australian Crawl",
                album: "The Boys Light Up"
            )
        )

        XCTAssertEqual(text.title, "The Boys Light Up")
        XCTAssertEqual(text.artist, "Australian Crawl")
        XCTAssertEqual(text.album, "Triple M Melbourne 105.1")
    }

    func testMetadataEvaluationExplainsAdvertisingProgrammeAndTechnicalValues() {
        let advert = StreamTrackMetadataParser.evaluate(title: "Commercial Break", artist: "Station")
        XCTAssertEqual(advert.outcome, .rejectedTitle)
        XCTAssertEqual(advert.classificationHints, ["advertisement"])

        let programme = StreamTrackMetadataParser.evaluate(title: "KIIS MINIMIX", artist: "Various Artists")
        XCTAssertEqual(programme.outcome, .accepted)
        XCTAssertTrue(programme.classificationHints.contains("programme-label"))

        let marker = StreamTrackMetadataParser.evaluate(
            title: "Asset Spot 15.699 2026-10-14T06:41:01.564Z",
            artist: "Station"
        )
        XCTAssertEqual(marker.outcome, .rejectedTitle)
        XCTAssertTrue(marker.classificationHints.contains("technical-marker"))
    }

    func testMetadataEvaluationRecordsMissingAndMalformedValues() {
        XCTAssertEqual(StreamTrackMetadataParser.evaluate(title: "A song", artist: nil).outcome, .missingArtist)
        XCTAssertEqual(StreamTrackMetadataParser.evaluate(title: nil, artist: nil).outcome, .noValues)
        XCTAssertEqual(ABCNowPlayingParser.evaluate(Data("not json".utf8)).outcome, .malformedPayload)
        XCTAssertEqual(TritonNowPlayingParser.evaluate(Data("not xml".utf8)).outcome, .malformedPayload)
    }

    func testCompanionMetadataSourcesAreDerivedFromStationAndStreams() {
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "Nova 96.9",
            network: "Nova",
            streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/NOVA_969_AAC320.aac"
        )), .triton(mountName: "NOVA_969"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "KIIS 1011",
            network: "KIIS",
            streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/ARN_KIIS1011.mp3"
        )), .triton(mountName: "ARN_KIIS1011"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "GOLD104.3",
            network: "Gold",
            streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/ARN_GOLD1043_AAC.aac"
        )), .triton(mountName: "ARN_GOLD1043"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "Double J", network: "ABC", subnetwork: "Double J"
        )), .abc(serviceID: "DOUBLEJ"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "triple j", network: "ABC", subnetwork: "Triple J"
        )), .abc(serviceID: "TRIPLEJ"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "ABC Country", network: "ABC", subnetwork: "ABC Country"
        )), .abc(serviceID: "COUNTRY"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "ABC Classic 2", network: "ABC", subnetwork: "ABC Classic"
        )), .abc(serviceID: "CLASSIC2"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "ABC Jazz", network: "ABC", subnetwork: "ABC Jazz"
        )), .abc(serviceID: "JAZZ"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "ABC KIDS listen", network: "ABC", subnetwork: "ABC Kids listen"
        )), .abc(serviceID: "KIDSLISTEN"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "triple j Hottest", network: "ABC", subnetwork: "Triple J"
        )), .abc(serviceID: "H100"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "triple j Unearthed", network: "ABC", subnetwork: "Triple J"
        )), .abc(serviceID: "UNEARTHED"))
        XCTAssertNil(CompanionMetadataSource.source(for: station(
            name: "Triple M Melbourne 105.1", network: "Triple M",
            subnetwork: "Metro",
            musicGenre: "Rock",
            streamURL: "https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web"
        )))
        XCTAssertNil(CompanionMetadataSource.source(for: station(
            name: "The Fox Melbourne", network: "Hit Network", subnetwork: "Metro",
            musicGenre: "Contemporary Hits",
            streamURL: "https://sa46.scastream.com.au/live/3fox_128.stream/playlist.m3u8?dist=listnr-web"
        )))
        XCTAssertEqual(CompanionMetadataSource.unavailableReason(for: station(
            name: "The Fox Melbourne", network: "Hit Network", subnetwork: "Metro",
            musicGenre: "Contemporary Hits",
            streamURL: "https://sa46.scastream.com.au/live/3fox_128.stream/playlist.m3u8?dist=listnr-web"
        )), "sca-broadcast-uses-embedded-metadata")
        XCTAssertNil(CompanionMetadataSource.source(for: station(
            name: "hit 91.9 Bendigo", network: "Hit Network", subnetwork: "Regional",
            musicGenre: "Contemporary Hits",
            streamURL: "https://sa47.scastream.com.au/live/3bdg_32.stream/playlist.m3u8?dist=listnr-web"
        )))
        XCTAssertNil(CompanionMetadataSource.source(for: station(
            name: "Unclassified Triple M", network: "Triple M",
            musicGenre: "Classic Rock",
            streamURL: "https://sa47.scastream.com.au/live/test_128.stream/playlist.m3u8?dist=listnr-web"
        )))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "Triple M 80s", network: "Triple M", subnetwork: "Music",
            musicGenre: "Classic Hits",
            streamURL: "https://sa46.scastream.com.au/live/triplem80s_128.stream/playlist.m3u8?dist=listnr-web"
        )), .listnr(streamKey: "triplem80s"))
        XCTAssertEqual(CompanionMetadataSource.source(for: station(
            name: "Oldskool 90s Hits", network: "LiSTNR", musicGenre: "Oldies",
            streamURL: "https://sa46.scastream.com.au/live/3oldskool_128.stream/playlist.m3u8?dist=listnr-web"
        )), .listnr(streamKey: "3oldskool"))
        XCTAssertNil(CompanionMetadataSource.source(for: station(
            name: "LiSTNR News", network: "LiSTNR",
            musicGenre: "News",
            streamURL: "https://sa46.scastream.com.au/live/news_128.stream/playlist.m3u8?dist=listnr-web"
        )))
        XCTAssertEqual(CompanionMetadataSource.unavailableReason(for: station(
            name: "LiSTNR News", network: "LiSTNR", musicGenre: "News",
            streamURL: "https://sa46.scastream.com.au/live/news_128.stream/playlist.m3u8?dist=listnr-web"
        )), "listnr-station-not-music-focused")
        XCTAssertNil(CompanionMetadataSource.source(for: station(name: "Local FM", network: "Independent")))
    }

    func testLiSTNRDirectoryAndNowPlayingPayloads() {
        let directory = Data(#"{"data":{"stations":[{"audioStreams":[{"callSign":"3MMM_FM","url":"https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web"}]}]}}"#.utf8)
        XCTAssertEqual(LiSTNRDirectoryParser.callSign(in: directory, matching: "3mmm"), "3MMM_FM")

        let nowPlaying = Data(#"{"data":{"stations":[{"currentTrack":{"title":"Never Tear Us Apart","artistName":"INXS","albumName":"Kick"}}]}}"#.utf8)
        XCTAssertEqual(LiSTNRNowPlayingParser.evaluate(nowPlaying).metadata, StreamTrackMetadata(
            title: "Never Tear Us Apart", artist: "INXS", album: "Kick"
        ))
        let marker = Data(#"{"data":{"stations":[{"currentTrack":{"title":"Asset Link 31.8","artistName":"Triple M","albumName":null}}]}}"#.utf8)
        XCTAssertEqual(LiSTNRNowPlayingParser.evaluate(marker).outcome, .rejectedTitle)
        let acknowledgement = Data(#"{"data":{"message":"connected"}}"#.utf8)
        XCTAssertFalse(LiSTNRNowPlayingParser.containsStationPayload(acknowledgement))
        XCTAssertTrue(LiSTNRNowPlayingParser.containsStationPayload(nowPlaying))
    }

    func testMetadataDiagnosticTimelineTracksHeartbeatsSilenceAndAcceptedSongs() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = MetadataDiagnosticTimeline(startedAt: start, heartbeatInterval: 60, silenceWarningInterval: 120)
        let empty = StreamTrackMetadataParser.noCurrentTrackEvaluation()
        XCTAssertEqual(timeline.record(empty, at: start.addingTimeInterval(45))["lastAcceptedSongElapsedSeconds"], "45.0")
        XCTAssertFalse(timeline.successfulHeartbeatDue(at: start.addingTimeInterval(59)))
        XCTAssertTrue(timeline.successfulHeartbeatDue(at: start.addingTimeInterval(60)))
        XCTAssertNil(timeline.silenceWarningDue(at: start.addingTimeInterval(119)))
        XCTAssertEqual(timeline.silenceWarningDue(at: start.addingTimeInterval(120))?.number, 1)
        XCTAssertNil(timeline.silenceWarningDue(at: start.addingTimeInterval(121)))

        let song = StreamTrackMetadataParser.evaluate(title: "Fall At Your Feet", artist: "Crowded House")
        XCTAssertEqual(timeline.record(song, at: start.addingTimeInterval(130))["lastAcceptedSongElapsedSeconds"], "0.0")
        XCTAssertEqual(timeline.elapsedFields(at: start.addingTimeInterval(150))["lastTrackChangeElapsedSeconds"], "20.0")
        let repeatedSong = song.addingProviderDetails(["candidateTimestampAgeSeconds": "50.0"])
        let repeatedFields = timeline.record(repeatedSong, at: start.addingTimeInterval(180))
        XCTAssertEqual(repeatedFields["lastAcceptedSongElapsedSeconds"], "50.0")
        XCTAssertEqual(repeatedFields["lastDistinctCandidateElapsedSeconds"], "50.0")
        XCTAssertEqual(repeatedFields["lastUsableMetadataReceiptElapsedSeconds"], "0.0")
        XCTAssertEqual(repeatedFields["acceptedReceiptCount"], "2")
        XCTAssertEqual(repeatedFields["identicalAcceptedReceiptCount"], "1")
        XCTAssertEqual(timeline.elapsedFields(at: start.addingTimeInterval(180))["lastTrackChangeElapsedSeconds"], "50.0")
        XCTAssertNil(timeline.silenceWarningDue(at: start.addingTimeInterval(249)))
        XCTAssertEqual(timeline.silenceWarningDue(at: start.addingTimeInterval(300))?.number, 1)
    }

    func testStaleAndTechnicalCandidatesDoNotResetUsableMetadataSilence() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = MetadataDiagnosticTimeline(startedAt: start, silenceWarningInterval: 120)
        let marker = StreamTrackMetadataParser.evaluate(
            title: "Asset Stop 00:00 2026-10-14T07:59:59.918Z",
            artist: "Triple M"
        )
        let fields = timeline.record(marker, at: start.addingTimeInterval(125))

        XCTAssertEqual(marker.outcome, .rejectedTitle)
        XCTAssertEqual(fields["lastUsableMetadataReceiptState"], "none-this-session")
        XCTAssertEqual(fields["lastUsableMetadataReceiptElapsedSeconds"], "125.0")
        XCTAssertEqual(timeline.silenceWarningDue(at: start.addingTimeInterval(125))?.number, 1)
    }

    func testSameSongCanMergeRicherAlbumWithoutBecomingADifferentTrack() {
        let embedded = StreamTrackMetadata(title: "Never Tear Us Apart", artist: "INXS", album: nil)
        let companion = StreamTrackMetadata(title: "never tear us apart", artist: "inxs", album: "Kick")

        XCTAssertTrue(embedded.hasSameSong(as: companion))
        XCTAssertEqual(embedded.mergingAlbum(from: companion).album, "Kick")
    }

    func testMetadataFreshnessDetectsOldEmbeddedTimestampWithoutRejectingRecentMarker() {
        let policy = MetadataFreshnessPolicy(timestampMaximumAge: 180)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldTimestamp = formatter.string(from: now.addingTimeInterval(-181))
        let recentTimestamp = formatter.string(from: now.addingTimeInterval(-30))

        let old = StreamTrackMetadataParser.evaluate(title: "Asset Stop 00:00 \(oldTimestamp)", artist: "Station")
        XCTAssertEqual(policy.diagnosticDetails(for: old, at: now)["candidateTimestampStale"], "true")
        XCTAssertEqual(policy.embeddedTimestamp(in: old), now.addingTimeInterval(-181))

        let recent = StreamTrackMetadataParser.evaluate(title: "Asset Spot 15.6 \(recentTimestamp)", artist: "Station")
        XCTAssertEqual(policy.diagnosticDetails(for: recent, at: now)["candidateTimestampStale"], "false")
    }

    func testSCAHLSPlaybackURLGetsAUniqueSessionQueryWithoutDroppingExistingQuery() throws {
        let stream = StationStream(
            id: "stream",
            url: "https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web",
            label: "Test",
            format: "hls",
            codec: "aac",
            bitrate_kbps: 128,
            request_headers: [:]
        )
        let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        let url = try XCTUnwrap(StreamRequestPolicy.playbackURL(for: stream, sessionID: sessionID))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "dist" })?.value, "listnr-web")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "wirelessSession" })?.value, sessionID.uuidString.lowercased())
    }

    func testCompanionMetadataCannotBeClearedByEmptyEmbeddedMetadata() {
        XCTAssertFalse(MetadataSourceArbitration.shouldApplyEmptyResult(
            source: "embedded", companionEnabled: true, currentSource: "companion"
        ))
        XCTAssertFalse(MetadataSourceArbitration.shouldApplyEmptyResult(
            source: "embedded", companionEnabled: true, currentSource: nil
        ))
        XCTAssertTrue(MetadataSourceArbitration.shouldApplyEmptyResult(
            source: "embedded", companionEnabled: true, currentSource: "embedded"
        ))
        XCTAssertTrue(MetadataSourceArbitration.shouldApplyEmptyResult(
            source: "companion", companionEnabled: true, currentSource: "embedded"
        ))
    }

    func testTritonCompanionMetadataParsesAndUsesExistingFilter() {
        let music = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <nowplaying-info-list><nowplaying-info mountName="ARN_GOLD1043" type="track">
        <property name="cue_title"><![CDATA[Beautiful Day]]></property>
        <property name="track_album_name"><![CDATA[All That You Can't Leave Behind]]></property>
        <property name="track_artist_name"><![CDATA[U2]]></property>
        </nowplaying-info></nowplaying-info-list>
        """.utf8)
        XCTAssertEqual(TritonNowPlayingParser.parse(music), StreamTrackMetadata(
            title: "Beautiful Day", artist: "U2", album: "All That You Can't Leave Behind"
        ))

        let advert = Data("""
        <nowplaying-info-list><nowplaying-info type="track">
        <property name="cue_title">Commercial Break</property>
        <property name="track_artist_name">GOLD104.3</property>
        </nowplaying-info></nowplaying-info-list>
        """.utf8)
        XCTAssertNil(TritonNowPlayingParser.parse(advert))
    }

    func testABCCompanionMetadataParsesReleaseAndLeavesAssetLabelsVisible() {
        let music = Data("""
        {"mapiNow":{"title":"Ray Of Light","artist":"Madonna","releaseTitle":"Ray Of Light"}}
        """.utf8)
        XCTAssertEqual(ABCNowPlayingParser.parse(music), StreamTrackMetadata(
            title: "Ray Of Light", artist: "Madonna", album: "Ray Of Light"
        ))

        let marker = Data("""
        {"mapiNow":{"title":"Asset Spot 15.6","artist":"Station"}}
        """.utf8)
        XCTAssertEqual(ABCNowPlayingParser.parse(marker)?.title, "Asset Spot 15.6")

        let validGap = ABCNowPlayingParser.evaluate(Data(#"{"mapiNow":null,"mapiPrev":{"title":"Previous"}}"#.utf8))
        XCTAssertEqual(validGap.outcome, .noCurrentTrack)
        XCTAssertEqual(validGap.classificationHints, ["no-current-track"])
        XCTAssertEqual(validGap.outcome.rawValue, "empty.no-current-track")
        XCTAssertEqual(validGap.providerDetails["abcPreviousTitle"], "Previous")
        XCTAssertEqual(validGap.providerDetails["payloadShape"], "mapiNow-null")
    }

    func testAssetSpotIsRejectedAsAnExactTechnicalMarker() {
        let marker = "Asset Spot 15.6997349102773 2026-10-14T06:41:01.564Z"
        let evaluation = StreamTrackMetadataParser.evaluate(title: marker, artist: marker)
        XCTAssertEqual(evaluation.outcome, .rejectedTitle)
        XCTAssertNil(evaluation.metadata)
        XCTAssertTrue(evaluation.classificationHints.contains("technical-marker"))
    }

    func testAssetStopIsRejectedAsAnExactTechnicalMarker() {
        let marker = "Asset Stop 00:00 2026-10-14T07:59:59.918Z"
        XCTAssertNil(StreamTrackMetadataParser.validated(title: marker, artist: marker))
    }

    func testAssetLinkIsRejectedAsAnExactTechnicalMarker() {
        let marker = "Asset Link 31.8178868383695 2026-10-17T07:29:41.388Z"
        let evaluation = StreamTrackMetadataParser.evaluate(title: marker, artist: marker)
        XCTAssertEqual(evaluation.outcome, .rejectedTitle)
        XCTAssertTrue(evaluation.classificationHints.contains("technical-marker"))
        XCTAssertNil(evaluation.metadata)
    }

    func testOtherAssetLabelsRemainVisibleButDiagnosable() {
        let marker = "Asset Fill 2.05653846153846 2026-10-17T19:31:43.940Z"
        let evaluation = StreamTrackMetadataParser.evaluate(title: marker, artist: marker)
        XCTAssertEqual(evaluation.outcome, .accepted)
        XCTAssertEqual(evaluation.metadata?.title, marker)
        XCTAssertTrue(evaluation.classificationHints.contains("technical-marker"))
    }

    func testGenuineMusicIsNotRejectedForAdvertisingRelatedSubstrings() {
        for title in ["Advertising Space", "Advertising", "Commercial", "Spotlight", "Mad World", "Commercial for Levi", "Asset Spotlight", "Asset Stopping"] {
            let track = StreamTrackMetadataParser.validated(title: title, artist: "A Band")
            XCTAssertEqual(track?.title, title)
        }
    }

    func testCombinedICYTitleAndWhitespaceAreNormalised() {
        for separator in [" - ", " – ", " — "] {
            let track = StreamTrackMetadataParser.validated(title: "  Crowded House\(separator)Don't Dream It's Over  ", artist: nil)
            XCTAssertEqual(track?.title, "Don't Dream It's Over")
            XCTAssertEqual(track?.artist, "Crowded House")
            XCTAssertEqual(track?.displayTitle, "Don't Dream It's Over · Crowded House")
        }
        XCTAssertEqual(StreamTrackMetadataParser.validated(title: "  A\n Song ", artist: " A\tBand ")?.title, "A Song")
        let evaluation = StreamTrackMetadataParser.evaluate(title: "  A\n Song ", artist: " A\tBand ")
        XCTAssertEqual(evaluation.rawTitle, "  A\n Song ")
        XCTAssertEqual(evaluation.rawArtist, " A\tBand ")
        XCTAssertEqual(evaluation.diagnosticFields["receivedTitleRaw"], "  A\n Song ")
    }

    func testIncompleteAndRecognisedNonMusicMetadataFallsBackToStation() {
        XCTAssertNil(StreamTrackMetadataParser.validated(title: "A song", artist: nil))
        for title in ["Commercial Break", "Ad break", "Advertisement", "2026-10-14T06:41:01.564Z", "https://example.org/ad", "---", ""] {
            XCTAssertNil(StreamTrackMetadataParser.validated(title: title, artist: "Station"), title)
        }
    }

    func testAssetEventsClearTheDisplayAndTheNextSongDisplaysNormally() {
        var displayed = StreamTrackMetadataParser.validated(title: "Weather With You", artist: "Crowded House")
        XCTAssertNotNil(displayed)
        displayed = StreamTrackMetadataParser.validated(title: "Asset Spot 15.6 2026-10-14T06:41:01.564Z", artist: "Station")
        XCTAssertNil(displayed)
        displayed = StreamTrackMetadataParser.validated(title: "Asset Stop 00:00 2026-10-14T07:59:59.918Z", artist: "Station")
        XCTAssertNil(displayed)
        displayed = StreamTrackMetadataParser.validated(title: "Never Tear Us Apart", artist: "INXS")
        XCTAssertEqual(displayed?.displayTitle, "Never Tear Us Apart · INXS")
    }

    func testID3AndICYUseTheSameFilter() async {
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            return item
        }
        let music = await StreamTrackMetadataParser.parse([
            item(.commonIdentifierTitle, "Never Tear Us Apart"),
            item(.commonIdentifierArtist, "INXS"),
            item(.commonIdentifierAlbumName, "Kick")
        ])
        XCTAssertEqual(music, StreamTrackMetadata(title: "Never Tear Us Apart", artist: "INXS", album: "Kick"))
        let marker = await StreamTrackMetadataParser.parse([
            item(.icyMetadataStreamTitle, "Asset Spot 15.699 2026-10-14T06:41:01.564Z - Asset Spot 15.699")
        ])
        XCTAssertNil(marker)
        let icyMusic = await StreamTrackMetadataParser.parse([
            item(.icyMetadataStreamTitle, "INXS - Never Tear Us Apart")
        ])
        XCTAssertEqual(icyMusic?.artist, "INXS")
    }


    private func station(
        name: String,
        network: String,
        subnetwork: String? = nil,
        musicGenre: String? = nil,
        streamURL: String? = nil
    ) -> DirectoryStation {
        let streams = streamURL.map {
            [StationStream(
                id: "stream",
                url: $0,
                label: "Test",
                format: "aac",
                codec: "aac",
                bitrate_kbps: 128,
                request_headers: [:]
            )]
        } ?? []
        return DirectoryStation(
            id: "station-test",
            name: name,
            network: network,
            subnetwork: subnetwork,
            country: "AU",
            state: "VIC",
            cities: [],
            tags: [],
            music_genre: musicGenre,
            description: "",
            website_url: "",
            logo_url: "",
            preferred_stream_id: streams.first?.id,
            streams: streams
        )
    }
}
