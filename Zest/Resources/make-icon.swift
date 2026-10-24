// make-icon.swift — renders Zest/Resources/AppIcon.icns.
//
//   swiftc -O Resources/make-icon.swift -o /tmp/make-icon
//   /tmp/make-icon Resources/AppIcon.iconset
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
//
// The tile is the macOS Big Sur grid: an 824 pt rounded square inside a
// 1024 pt canvas, warm orange gradient, white `wand.and.stars` glyph — the
// same symbol the status item uses.

import AppKit

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: output, withIntermediateDirectories: true)

/// Draws the icon at `size` pixels square and returns the bitmap.
func render(_ size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size.rounded())
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)

    let margin = size * 100.0 / 1024.0
    let tile = NSRect(x: margin, y: margin,
                      width: size - margin * 2, height: size - margin * 2)
    let radius = tile.width * 0.225
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // Soft contact shadow so the tile reads on light backgrounds.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = size * 0.018
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.010)
    shadow.set()
    NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.10, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Warm gradient body.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let body = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.46, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.07, alpha: 1)
    ])!
    body.draw(in: tile, angle: -90)

    // Top gloss.
    let gloss = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.20),
        NSColor.white.withAlphaComponent(0.0)
    ])!
    gloss.draw(in: NSRect(x: tile.minX, y: tile.midY,
                          width: tile.width, height: tile.height * 0.5),
               angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim keeps the edge crisp at small sizes.
    NSColor.white.withAlphaComponent(0.16).setStroke()
    shape.lineWidth = max(1, size * 0.004)
    shape.stroke()

    // Wand-and-stars glyph, matching the status item.
    if let base = NSImage(systemSymbolName: "wand.and.stars",
                          accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(
            pointSize: size * 0.46, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = base.withSymbolConfiguration(config) {
            let aspect = symbol.size.height / max(symbol.size.width, 1)
            let box = size * 0.54
            let width = min(box, box / max(aspect, 0.001))
            let height = width * aspect
            let rect = NSRect(x: (size - width) / 2,
                              y: (size - height) / 2,
                              width: width, height: height)
            symbol.draw(in: rect, from: .zero,
                        operation: .sourceOver, fraction: 1)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, size) in variants {
    let rep = render(size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: output).appendingPathComponent("\(name).png")
    try data.write(to: url)
}
print("wrote \(variants.count) images to \(output)")
