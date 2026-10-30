import Combine
import Foundation
import CryptoKit
import UIKit
import WidgetKit

/// Adapted from Autohop's snapshot publisher. The extension reads atomic files;
/// networking, catalogue resolution and audio stay in the containing application.
@MainActor
final class WidgetSnapshotCoordinator {
    private var subscriptions = Set<AnyCancellable>()
    private var publication: Task<Void, Never>?
    private let storage = WidgetSharedStorage()
    private var previous: WidgetSnapshot?

    init(player: MobilePlayer) {
        Publishers.CombineLatest3(player.$station, player.$requested, player.library.$favourites)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self, weak player] _ in
                guard let player else { return }
                self?.publish(player: player)
            }.store(in: &subscriptions)
        publish(player: player)
    }

    func publish(player: MobilePlayer) {
        let current = player.hasDetails ? player.station : nil
        let favourites = Array(player.library.favourites.prefix(7))
        func display(_ station: DirectoryStation) -> WidgetDisplayStation {
            let digest = SHA256.hash(data: Data((station.id + "|" + station.logo_url).utf8))
            let filename = digest.map { String(format: "%02x", $0) }.joined() + ".png"
            return WidgetDisplayStation(id: station.id, name: station.name,
                subtitle: station.network, thumbnailFilename: station.logo_url.isEmpty ? nil : filename)
        }
        let snapshot = WidgetSnapshot(schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: Date(), current: current.map(display), favourites: favourites.map(display),
            isPlaying: player.requested)
        // Playback progress generates many changes. Reload only meaningful display changes.
        if let previous, previous.current == snapshot.current,
           previous.favourites == snapshot.favourites, previous.isPlaying == snapshot.isPlaying { return }
        do {
            try storage.write(snapshot)
            previous = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConfiguration.widgetKind)
        } catch {
            NSLog("Wireless widget snapshot: %@", error.localizedDescription)
            return
        }
        publication?.cancel()
        publication = Task { [storage] in
            var seen = Set<String>()
            for station in ([current].compactMap { $0 } + favourites) {
                guard !Task.isCancelled else { return }
                guard seen.insert(station.id).inserted,
                      let filename = display(station).thumbnailFilename,
                      let url = URL(string: station.logo_url), url.scheme == "https" else { continue }
                do {
                    let destination = try storage.thumbnailURL(filename: filename)
                    if FileManager.default.fileExists(atPath: destination.path) { continue }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 15
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                          data.count <= 5 * 1_024 * 1_024, let image = UIImage(data: data),
                          image.size.width > 0, image.size.height > 0 else { continue }
                    let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
                        UIColor.white.setFill()
                        context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
                        let scale = min(160 / image.size.width, 160 / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (160 - size.width) / 2, y: (160 - size.height) / 2,
                                              width: size.width, height: size.height))
                    }
                    if let data = thumbnail.pngData() { try storage.writeThumbnail(data, filename: filename) }
                } catch { /* Station name and fallback artwork remain available offline. */ }
            }
            guard !Task.isCancelled else { return }
            let retained = Set(([snapshot.current].compactMap { $0 } + snapshot.favourites).compactMap(\.thumbnailFilename))
            try? storage.removeThumbnails(except: retained)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConfiguration.widgetKind)
        }
    }
}
