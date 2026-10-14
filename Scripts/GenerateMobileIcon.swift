import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(starting: NSColor(calibratedRed: 0.57, green: 0.18, blue: 0.85, alpha: 1), ending: NSColor(calibratedRed: 0.14, green: 0.04, blue: 0.25, alpha: 1))!.draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)), angle: -55)
NSColor.white.setFill()
for (index, height) in [130.0, 280, 450, 610, 360, 210, 120].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 202 + Double(index) * 90, y: (1024 - height) / 2, width: 60, height: height), xRadius: 30, yRadius: 30).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
