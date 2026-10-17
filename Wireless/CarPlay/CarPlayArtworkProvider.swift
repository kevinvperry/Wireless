import CarPlay
import UIKit

// ============================================================================
// AI CONTEXT - CarPlay/CarPlayArtworkProvider.swift
//
// PURPOSE: Non-SwiftUI artwork adapter for CarPlay templates, adapted from
// Autohop's CarPlayArtworkProvider. CarPlay list rows need display-ready
// UIImages, so this provider loads station logos, flattens them onto white (as
// StationImage and the Now Playing artwork do, because many logos are
// transparent) and always supplies a placeholder immediately so slow or failed
// artwork never blocks the CarPlay lists.
// ============================================================================

@MainActor
final class CarPlayArtworkProvider {
    private let placeholder: UIImage
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        let size = CPListItem.maximumImageSize
        let side = max(48, min(size.width, size.height))
        placeholder = Self.makePlaceholder(size: CGSize(width: side, height: side))
    }

    func placeholderImage() -> UIImage {
        placeholder
    }

    func cachedImage(for station: DirectoryStation) -> UIImage? {
        logoURL(for: station).flatMap { cache.object(forKey: $0 as NSURL) }
    }

    func image(for station: DirectoryStation) async -> UIImage {
        await image(for: logoURL(for: station))
    }

    /// `background` fills transparent areas. Station logos use white; the iPhone
    /// Networks page shows ARN's artwork on black, so callers can match that.
    func image(for url: URL?, background: UIColor = .white) async -> UIImage {
        guard let url, url.scheme?.lowercased() == "https" else { return placeholder }
        let key = (background == .white ? url : url.appending(queryItems: [URLQueryItem(name: "carplay-background", value: background.description)])) as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = UIImage(data: data),
                  source.size.width > 0, source.size.height > 0 else { return placeholder }
            let image = Self.squareBacked(source, background: background)
            cache.setObject(image, forKey: key)
            return image
        } catch {
            return placeholder
        }
    }

    private func logoURL(for station: DirectoryStation) -> URL? {
        guard let url = URL(string: station.logo_url), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func squareBacked(_ source: UIImage, background: UIColor) -> UIImage {
        let size = CPListItem.maximumImageSize
        let side = max(48, min(size.width, size.height))
        let canvas = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let scale = max(canvas.width / source.size.width, canvas.height / source.size.height)
            let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: CGRect(x: (canvas.width - drawn.width) / 2,
                                   y: (canvas.height - drawn.height) / 2,
                                   width: drawn.width,
                                   height: drawn.height))
        }
    }

    private static func makePlaceholder(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.18).fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.42, weight: .semibold)
            let symbol = UIImage(systemName: "waveform", withConfiguration: symbolConfig)?
                .withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
            let symbolSize = symbol?.size ?? .zero
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            symbol?.draw(in: CGRect(origin: symbolOrigin, size: symbolSize))

            UIColor.white.withAlphaComponent(0.12).setStroke()
            UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: size.width * 0.18)
                .stroke()
        }
    }
}
