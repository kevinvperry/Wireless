import XCTest
import SwiftUI
import WidgetKit

@MainActor
final class WidgetLayoutTests: XCTestCase {
    func testWidgetLayoutGallery() throws {
        let variants: [(String, WidgetFamily, CGFloat, CGFloat)] = [
            ("small-phone", .systemSmall, 158, 158),
            ("small-phone-light", .systemSmall, 158, 158),
            ("medium-phone", .systemMedium, 338, 158),
            ("large-phone", .systemLarge, 338, 354),
            ("large-pro-max", .systemLarge, 364, 382),
            ("large-ipad", .systemLarge, 360, 379),
            ("medium-ipad", .systemMedium, 360, 170),
            ("extra-large-ipad", .systemExtraLarge, 715, 342),
            ("lock-circular", .accessoryCircular, 76, 76),
            ("lock-rectangular", .accessoryRectangular, 160, 76)
        ]
        for (name, family, width, height) in variants {
            let view = StationWidgetView(entry: .preview, family: family)
                .environment(\.colorScheme, name.hasSuffix("-light") ? .light : .dark)
                .padding(family == .accessoryCircular || family == .accessoryRectangular ? 0 : 16)
                .frame(width: width, height: height)
                .background {
                    if family == .accessoryCircular || family == .accessoryRectangular {
                        Color.black
                    } else {
                        WirelessWidgetCharcoalGlassBackground()
                    }
                }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WirelessWidgetLayouts")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.pngData()?.write(to: folder.appendingPathComponent(name + ".png"))
            print("Widget layout: \(folder.path)/\(name).png")
        }
    }
}
