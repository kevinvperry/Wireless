import Foundation
import Combine

struct StationStream: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let url: String
    let label: String
    let format: String
    let codec: String
    let bitrate_kbps: Double?
    let request_headers: [String: String]

    var playableURL: URL? {
        guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? ""), value.host != nil else { return nil }
        return value
    }
    var isSupported: Bool {
        playableURL != nil && ["hls", "mp3", "aac", "flac"].contains(format)
            && (format != "hls" || request_headers.keys.allSatisfy { $0.lowercased() == "user-agent" })
    }
    /// Formats that Wireless can retain as individual compressed audio packets.
    /// AAC HLS is supported when its segments contain an AAC elementary stream;
    /// other HLS containers continue through AVPlayer.
    var supportsPacketBuffer: Bool {
        ["mp3", "aac"].contains(format) || (format == "hls" && codec.lowercased().contains("aac"))
    }
    var title: String {
        format.uppercased() + (bitrate_kbps.map { " · \(Int($0.rounded())) kbps" } ?? "") + (label.isEmpty ? "" : " · \(label)")
    }
}

struct DirectoryStation: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let network: String
    var subnetwork: String? = nil
    let country: String
    let state: String
    let cities: [String]
    let tags: [String]
    var frequency: String? = nil
    var metro_regional: String? = nil
    var tagline: String? = nil
    var genres: [String]? = nil
    var music_genre: String? = nil
    var browse_genres: [String]? = nil
    let description: String
    let website_url: String
    let logo_url: String
    var contact: StationContact? = nil
    let preferred_stream_id: String?
    let streams: [StationStream]

    var isSEN: Bool { network.caseInsensitiveCompare("SEN") == .orderedSame }
    /// SEN's programme endpoint requires the channel identifier used by its
    /// radio player. Keep this separate from Wireless station identifiers so
    /// every SEN network feed can request its own local schedule.
    var senChannelID: String? {
        guard isSEN else { return nil }
        return Self.senChannelIDs[id]
    }
    var taptProgrammeSource: (website: URL, timeZoneIdentifier: String)? {
        switch id {
        case "station_47cd29da5a1d": return (URL(string: "https://www.3aw.com.au/")!, "Australia/Melbourne")
        case "station_44dd138bd4c1": return (URL(string: "https://www.2gb.com/")!, "Australia/Sydney")
        case "station_db432bcf4c61": return (URL(string: "https://www.4bc.com.au/")!, "Australia/Brisbane")
        case "station_3f29cc24820d": return (URL(string: "https://www.6pr.com.au/")!, "Australia/Perth")
        default: return nil
        }
    }
    /// Official ABC service identifiers, independent of display names and stream hosts.
    var abcProgrammeServiceID: String? {
        guard network.caseInsensitiveCompare("ABC") == .orderedSame else { return nil }
        return Self.abcProgrammeServiceIDs[id]
    }

    private static let abcProgrammeServiceIDs: [String: String] = [
        "station_7de64417a171": "LOCAL_ADELAIDE", // ABC Adelaide
        "station_60fc0bebc191": "ITINERANT_ONE", // ABC AFL
        "station_ee997462d2e1": "ABC_AFL_RAPID", // ABC AFL RAPID
        "station_c50a27e9c288": "ITINERANT_TWO", // ABC AFLW
        "station_0a8787bf2108": "LOCAL_ALICESPRINGS", // ABC Alice Springs
        "station_14507c9b8ceb": "LOCAL_BALLARAT", // ABC Ballarat
        "station_53134d345305": "LOCAL_BRISBANE", // ABC Brisbane
        "station_4bf3194e1a9e": "LOCAL_BROKENHILL", // ABC Broken Hill
        "station_15e980155375": "LOCAL_CANBERRA", // ABC Canberra
        "station_9772a310b0e3": "LOCAL_CAPRICORNIA", // ABC Capricornia
        "station_99b3bb19eb43": "LOCAL_CENTRALCOAST", // ABC Central Coast
        "station_73a1d390e062": "LOCAL_CENTRALVIC", // ABC Central Victoria
        "station_c002afafbc41": "LOCAL_CENTRALWEST", // ABC Central West
        "station_93680e18e95a": "LOCAL_COFFSCOAST", // ABC Coffs Coast
        "station_a8c2f7d8d6dc": "ITINERANT_FOUR", // ABC CRICKET
        "station_941a34adbebd": "LOCAL_DARWIN", // ABC Darwin
        "station_653201ae289d": "LOCAL_ESPERANCE", // ABC Esperance
        "station_a90da22ac432": "LOCAL_EYRE", // ABC Eyre Peninsula
        "station_c4c205df6e7e": "LOCAL_FARNORTH", // ABC Far North
        "station_4801b9905447": "LOCAL_GIPPSLAND", // ABC Gippsland
        "station_a309cb38ecac": "LOCAL_GOLDCOAST", // ABC Gold Coast
        "station_3dad42887bb6": "LOCAL_GOLDFIELDS", // ABC Goldfields
        "station_2343ffe24282": "LOCAL_GOULBURNMURRAY", // ABC Goulburn Murray
        "station_d3534adbb7fe": "LOCAL_GREATSOUTHERN", // ABC Great Southern
        "station_d1fe63732c57": "LOCAL_HOBART", // ABC Hobart
        "station_43c5f5ca49bb": "LOCAL_ILLAWARRA", // ABC Illawarra
        "station_762cbfe271d7": "LOCAL_KIMBERLEY", // ABC Kimberley
        "station_f9e327bf23a1": "LOCAL_MELBOURNE", // ABC Melbourne
        "station_e5533eeadc62": "LOCAL_MIDNORTHCOAST", // ABC Mid North Coast
        "station_0650f64f78c5": "LOCAL_WHEATBELT", // ABC Midwest & Wheatbelt
        "station_e9e997dad3ec": "LOCAL_MILDURASWANHILL", // ABC Mildura-Swan Hill
        "station_039505caff2c": "LOCAL_NEWENGLAND", // ABC New England North West
        "station_d73098a08ad5": "LOCAL_NEWCASTLE", // ABC Newcastle
        "station_57237cd688e3": "NEWS", // ABC NewsRadio
        "station_948704c88060": "LOCAL_NORTHANDWEST", // ABC North and West SA
        "station_7036414f3e12": "LOCAL_NORTHCOAST", // ABC North Coast
        "station_9b4c00d98e3f": "LOCAL_NORTHQLD", // ABC North Queensland
        "station_4dbd91d2af75": "LOCAL_NORTHWEST", // ABC North West Queensland
        "station_e9bf6a5ac6cc": "LOCAL_NORTHTAS", // ABC Northern Tasmania
        "station_1b89f545bcf2": "LOCAL_PERTH", // ABC Perth
        "station_0eddffb877dd": "LOCAL_NORTHWESTWA", // ABC Pilbara
        "station_fd471a4b1ded": "RA", // ABC Radio Australia
        "station_1a92d25435ee": "RN", // ABC Radio National
        "station_6a02d43112fd": "RN_NT", // ABC Radio National (NT)
        "station_bbaa8d5649e5": "RN_QLD", // ABC Radio National (QLD)
        "station_9c938af92e05": "RN_SA", // ABC Radio National (SA)
        "station_007624180058": "RN_TAS", // ABC Radio National (TAS)
        "station_0c3d40dfa76e": "RN_VIC", // ABC Radio National (VIC)
        "station_7979e56607a5": "RN_WA", // ABC Radio National (WA)
        "station_a7d2616a45cc": "LOCAL_RIVERINA", // ABC Riverina
        "station_a7c8c38f021e": "LOCAL_RIVERLAND", // ABC Riverland
        "station_62502aba32b2": "LOCAL_SHEPPARTON", // ABC Shepparton
        "station_e4675602c7cb": "LOCAL_SOUTHEASTNSW", // ABC South East NSW
        "station_7acfc90b06ff": "LOCAL_SOUTHEASTSA", // ABC South East SA
        "station_28e4cf3b5f8a": "LOCAL_SOUTHWESTVIC", // ABC South West Victoria
        "station_2937be8bf5b5": "LOCAL_SOUTHWESTWA", // ABC South West WA
        "station_49102dcadfd8": "LOCAL_SOUTHQLD", // ABC Southern Queensland
        "station_eca1f2e3e975": "GRANDSTAND", // ABC Sport
        "station_449b4872a200": "ITINERANT_THREE", // ABC SPORT EXTRA
        "station_55386dde3229": "ABCSPORTSYNC", // ABC SPORT RAPID
        "station_b390cf220927": "LOCAL_SUNSHINE", // ABC Sunshine Coast
        "station_11264c4bac29": "LOCAL_SYDNEY", // ABC Sydney
        "station_f69e36284be1": "LOCAL_TROPIC", // ABC Tropical North
        "station_d45ea3d63457": "LOCAL_UPPERHUNTER", // ABC Upper Hunter
        "station_a50cc1574153": "LOCAL_WESTERNPLAINS", // ABC Western Plains
        "station_4d2e56d87173": "LOCAL_WESTQLD", // ABC Western Queensland
        "station_2bc5fa3b1ff6": "LOCAL_WIDEBAY", // ABC Wide Bay
        "station_7f296c08035f": "LOCAL_WESTERNVIC", // ABC Wimmera
    ]

    var location: String { cities.isEmpty ? [state, country].filter { !$0.isEmpty }.joined(separator: " · ") : cities.joined(separator: ", ") }
    var playableStreams: [StationStream] { streams.filter(\.isSupported) }
    var preferredStream: StationStream? {
        playableStreams.first { $0.id == preferred_stream_id } ?? playableStreams.first
    }
    static let sen = DirectoryStation(id: "station_62d2e55ae9ff", name: "SEN 1116", network: "SEN", country: "AU", state: "VIC", cities: ["Melbourne"], tags: ["Sport"], description: "Live sport and commentary", website_url: "https://www.sen.com.au", logo_url: "", preferred_stream_id: "sen-hls", streams: [
        StationStream(id: "sen-hls", url: "https://d2jt3l9ulybyg4.cloudfront.net/chunklist.m3u8?key=monash", label: "SEN", format: "hls", codec: "aac", bitrate_kbps: 64, request_headers: [:]),
        StationStream(id: "sen-mp3", url: "http://13.54.221.214:8000/sen.mp3", label: "SEN", format: "mp3", codec: "mp3", bitrate_kbps: 64, request_headers: [:])
    ])
    static let unselected = DirectoryStation(id: "unselected", name: "Choose a station", network: "", country: "AU", state: "", cities: [], tags: [], description: "", website_url: "", logo_url: "", preferred_stream_id: nil, streams: [])

    private static let senChannelIDs: [String: String] = [
        "station_89386739b7e6": "f5846530-8622-11f0-a38b-f905d48133cb", // RSN
        "station_c487b473ce92": "6bf94350-9db3-11f0-aee0-f71b34d2df5e", // RSN Ballarat
        "station_75afc2ee00aa": "ca8250e0-8edd-11f0-912c-bb34a7be1706", // RSN Bendigo & Wangaratta
        "station_62d2e55ae9ff": "33bca489-db01-41a9-ade9-3274da58052c", // SEN 1116
        "station_612f55de42a8": "2fc915f1-78a8-4f38-bcc0-0ed9a2ee5f88", // SEN 1170
        "station_f35311b305ad": "3d81de76-bf9a-4425-982e-ceb5b8afe105", // SEN Fanatic
        "station_2942c7a1e287": "85e6eae1-3dd2-4b95-b537-f0444b55f356", // SEN Geelong
        "station_3ec4ee0929b9": "2124875c-4b37-4faf-97c4-cbf7785a3031", // SEN Gold Coast
        "station_abb1a6a79758": "c103fef0-9428-11ec-a1ee-7bf50d641a74", // SEN Goldfields
        "station_5f07a4a62c66": "2d8c3340-0e0d-11ed-956d-dd3daed9230c", // SEN Goulburn Valley
        "station_6fba51f6ebe8": "9664eb52-7e4c-4199-8545-1864192c2ac8", // SEN Mount Gambier
        "station_a523d31feb62": "2acffd05-a4d3-4253-8376-77aef6bce21e", // SEN Peel
        "station_ce7d49d13fcb": "09fb8fef-ecca-45e4-bf82-f3d0c795f524", // SEN SA
        "station_10e363adfa69": "ed593cd2-29a2-4cf6-8d0a-3a96c66917bc", // SEN Spirit Bunbury
        "station_06990519fc20": "3db60681-e795-460d-b3bd-46a968df818f", // SEN Spirit Southwest
        "station_c0decfdb0d7a": "f9150878-5d4b-405c-a72c-70be838d77a4", // SEN Tassie
        "station_3b78fdea2a3d": "6912a3fe-f073-4912-b59e-991069abb0e5", // SEN Top End
        "station_d5b048a58b08": "619f8997-f065-48bd-876f-4089504e6ee4", // SEN Track
        "station_eb0f043e3612": "73a0c341-81fc-4e96-930c-dfd7b10ee4b6", // SEN Track Brisbane
        "station_6e88b935dc42": "aba95740-f0ed-11ec-aa5e-7590457a63ca", // SEN Track Canberra
        "station_94a03f77ca1d": "0ccf752e-cbf5-4e13-b791-c72a7ae2bed4", // SEN Track Central Coast
        "station_581099effcd6": "b7395315-70c0-4820-bb76-78733a707a0f", // SEN Track Darling Downs
        "station_18f60d45d099": "e0506c25-fe71-46df-b4bb-cb425d21c893", // SEN Track Illawarra
        "station_ca591fdab56a": "39bfbe7a-7dfa-4d6a-bfc4-3a9c46873963", // SEN Track Ingham
        "station_c102a7dbd259": "3d8fd0bd-7b27-41d1-bd62-4f24430a5ad0", // SEN Track Kingaroy
        "station_23eddcf17d31": "7d020f1f-ab3f-40cb-80df-dfa3b3fd6405", // SEN Track Latrobe Valley
        "station_df73e8475126": "824b5f70-4427-42bb-a0f2-4fe6fa5f87d3", // SEN Track Launceston
        "station_a053118845ee": "619f8997-f065-48bd-876f-4089504e6ee4", // SEN Track Melbourne
        "station_c7173a40f9ca": "de540440-24a3-11ec-9b40-ebab8db0b0b8", // SEN Track South West Gippsland
        "station_f361b9b1ea73": "b6267fff-6545-4a71-ac85-4f058cf4dca1", // SEN Track Sunraysia
        "station_3fb703b66c24": "bf191d8d-d9fd-4bfe-ae8b-4d64a19ae9b8", // SEN Track Sydney
        "station_3f125fd26f9b": "dbc729d0-fdd8-11ee-8aa2-a327276c98a9", // SEN Track Top End
        "station_75b01091724e": "8b8373c2-111e-4f9f-8872-38fb4f2dbd36", // SEN Track WA
        "station_25bd51eca1c1": "c5907b70-be8a-11f0-ba1f-9d144a85cdbe", // SEN Turf Perth
        "station_b94a294d47ae": "15ef38d5-1ecb-4f3c-b736-f12303b41cb5", // SEN WA
        "station_7ea2e37443b4": "d367d900-5719-11ec-85cf-fb928f53ebff" // SENQ
    ]
}

struct StationContact: Codable, Equatable, Sendable {
    var talkback_phone: String? = nil
    var sms: String? = nil
    var office_phone: String? = nil
    var email: String? = nil
    var address: String? = nil
    var contact_page: String? = nil
}

struct CataloguePage: Decodable, Sendable {
    let schema_version: Int
    let revision: Int
    let page: Int
    let total: Int
    let has_more: Bool
    let stations: [DirectoryStation]
}
struct CatalogueSnapshot: Codable {
    let revision: Int
    let date: Date
    let stations: [DirectoryStation]
    var networkArtwork: [NetworkArtwork]? = nil
}

struct NetworkArtwork: Codable, Equatable, Sendable {
    let network: String
    let image_url: String
}

private struct NetworkArtworkPage: Decodable {
    let schema_version: Int
    let revision: Int
    let networks: [NetworkArtwork]
}

enum CatalogueError: LocalizedError {
    case invalidResponse, changedDuringRefresh
    var errorDescription: String? { "The directory could not refresh. Please try again." }
}

struct CatalogueClient: Sendable {
    var baseURL = URL(string: "https://wireless-directory.kevin-453.workers.dev")!
    var session: URLSession = .shared

    func revision() async throws -> Int {
        struct Revision: Decodable { let schema_version: Int; let revision: Int }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/catalogue"))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogueError.invalidResponse }
        let result = try JSONDecoder().decode(Revision.self, from: data)
        guard result.schema_version == 1 else { throw CatalogueError.invalidResponse }
        return result.revision
    }

    func fetch() async throws -> CatalogueSnapshot {
        // Publish only a complete revision, never a partial collection of pages.
        for _ in 0..<2 {
            var stations: [DirectoryStation] = [], revision: Int?, total = 0
            for page in 1...100 {
                try Task.checkCancellation()
                let url = baseURL.appendingPathComponent("api/v1/stations").appending(queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "100")])
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.cachePolicy = .reloadRevalidatingCacheData
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogueError.invalidResponse }
                let result = try JSONDecoder().decode(CataloguePage.self, from: data)
                guard result.schema_version == 1, result.page == page else { throw CatalogueError.invalidResponse }
                if let revision, revision != result.revision { break }
                revision = result.revision; total = result.total
                stations += result.stations
                if !result.has_more {
                    guard stations.count == total, Set(stations.map(\.id)).count == total else { throw CatalogueError.invalidResponse }
                    var artworkRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/networks"))
                    artworkRequest.timeoutInterval = 20
                    artworkRequest.cachePolicy = .reloadRevalidatingCacheData
                    let (artworkData, artworkResponse) = try await session.data(for: artworkRequest)
                    guard (artworkResponse as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogueError.invalidResponse }
                    let artwork = try JSONDecoder().decode(NetworkArtworkPage.self, from: artworkData)
                    guard artwork.schema_version == 1, artwork.revision == result.revision else { break }
                    return CatalogueSnapshot(revision: result.revision, date: Date(), stations: stations, networkArtwork: artwork.networks)
                }
            }
        }
        throw CatalogueError.changedDuringRefresh
    }
}

@MainActor final class StationLibrary: ObservableObject {
    @Published private(set) var stations: [DirectoryStation] = []
    @Published private(set) var networkArtwork: [NetworkArtwork] = []
    @Published private(set) var favourites: [DirectoryStation] = []
    @Published private(set) var recents: [DirectoryStation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var refreshedAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var revision: Int?
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let client: CatalogueClient

    init(defaults: UserDefaults = .standard, cacheURL: URL? = nil, client: CatalogueClient = CatalogueClient()) {
        self.defaults = defaults; self.client = client
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wireless/catalogue-v1.json")
        if let data = try? Data(contentsOf: self.cacheURL), let snapshot = try? JSONDecoder().decode(CatalogueSnapshot.self, from: data) {
            stations = snapshot.stations; networkArtwork = snapshot.networkArtwork ?? []; refreshedAt = snapshot.date; revision = snapshot.revision
        }
        if let data = defaults.data(forKey: "stationFavourites.v1"), let saved = try? JSONDecoder().decode([DirectoryStation].self, from: data) { favourites = saved }
        else {
            favourites = defaults.object(forKey: "senFavourite") as? Bool == true ? [.sen] : []
            saveFavourites()
        }

        if let data = defaults.data(forKey: Self.recentsKey), let saved = try? JSONDecoder().decode([DirectoryStation].self, from: data) { recents = saved }
    }
    static let recentsKey = "stationRecents.v1"
    static let recentsLimit = 10
    /// Most recently played first. Used by CarPlay's Recently Played list.
    func recordRecent(_ station: DirectoryStation) {
        guard station.id != DirectoryStation.unselected.id else { return }
        recents.removeAll { $0.id == station.id }
        recents.insert(station, at: 0)
        if recents.count > Self.recentsLimit { recents.removeLast(recents.count - Self.recentsLimit) }
        saveRecents()
    }
    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Self.recentsKey) }
    }
    func contains(_ station: DirectoryStation) -> Bool { favourites.contains { $0.id == station.id } }
    func toggle(_ station: DirectoryStation) {
        if contains(station) { favourites.removeAll { $0.id == station.id } } else { favourites.append(station) }
        saveFavourites()
    }
    func moveFavourites(from source: IndexSet, to destination: Int) {
        favourites.move(fromOffsets: source, toOffset: destination)
        saveFavourites()
    }
    func moveFavourite(_ id: String, to targetID: String) {
        guard id != targetID,
              let source = favourites.firstIndex(where: { $0.id == id }),
              let target = favourites.firstIndex(where: { $0.id == targetID }) else { return }
        let station = favourites.remove(at: source)
        favourites.insert(station, at: min(target, favourites.endIndex))
        saveFavourites()
    }
    private func saveFavourites() {
        if let data = try? JSONEncoder().encode(favourites) { defaults.set(data, forKey: "stationFavourites.v1") }
    }
    func refresh() async {
        // Navigation can cancel the departing view's task while the next page
        // requests the same catalogue. Share work independently of either view.
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await self.refreshCatalogue() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
    private func refreshCatalogue() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            if let revision, try await client.revision() == revision { return }
            let snapshot = try await client.fetch()
            stations = snapshot.stations; networkArtwork = snapshot.networkArtwork ?? []; refreshedAt = snapshot.date; revision = snapshot.revision
            let lookup = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
            favourites = favourites.map { lookup[$0.id] ?? $0 }; saveFavourites()
            recents = recents.map { lookup[$0.id] ?? $0 }; saveRecents()
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
            } catch { self.error = "Stations refreshed, but offline storage is unavailable." }
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch { self.error = "Couldn’t refresh the directory. Showing saved stations. Check your connection and retry." }
    }
    func available(_ station: DirectoryStation) -> Bool { stations.contains { $0.id == station.id } }
    var musicGenres: [String] {
        Array(Set(stations.flatMap { station in
            [station.music_genre].compactMap { $0 } + (station.browse_genres ?? [])
        }.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var networks: [String] { Array(Set(stations.map(\.network).filter { !$0.isEmpty })).sorted() }
    func networkArtworkURL(for network: String) -> URL? {
        guard let value = networkArtwork.first(where: { $0.network == network })?.image_url else { return nil }
        return URL(string: value)
    }
    var cities: [String] { Array(Set(stations.flatMap(\.cities))).sorted() }
    func results(favouritesOnly: Bool, query: String, network: String, city: String, state: String = "", subnetwork: String = "", musicGenre: String = "") -> [DirectoryStation] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = (favouritesOnly ? favourites : stations).filter {
            (musicGenre.isEmpty || $0.music_genre == musicGenre || ($0.browse_genres ?? []).contains { $0.caseInsensitiveCompare(musicGenre) == .orderedSame }) && (network.isEmpty || $0.network == network) && (subnetwork.isEmpty || $0.subnetwork == subnetwork) && (city.isEmpty || $0.cities.contains(city)) &&
            (state.isEmpty || $0.state.caseInsensitiveCompare(state) == .orderedSame) &&
            (words.isEmpty || [$0.name, $0.network, $0.subnetwork ?? "", $0.music_genre ?? "", ($0.genres ?? []).joined(separator: " "), $0.location, $0.tags.joined(separator: " ")].joined(separator: " ").localizedStandardContains(words))
        }
        return favouritesOnly ? matches : matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
