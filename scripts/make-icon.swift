import AppKit

// Editable vector artwork, rasterized at each native macOS icon size.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.03, green: 0.24, blue: 0.28, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.29, blue: 0.34, alpha: 1),
               ending: NSColor(calibratedRed: 0.13, green: 0.58, blue: 0.59, alpha: 1))!.draw(in: tile, angle: 90)
    let border = NSColor.white.withAlphaComponent(0.22)
    border.setStroke()
    tile.lineWidth = 3
    tile.stroke()
    // Spacious grid silhouette remains legible in Finder and the Dock.
    let xs: [CGFloat] = [236, 408, 614]
    let widths: [CGFloat] = [142, 176, 176]
    for y: CGFloat in [256, 396, 536, 676] {
        let active = y == 396
        if active {
            rounded(NSRect(x: 216, y: y - 16, width: 592, height: 130), 30,
                    NSColor(calibratedRed: 0.76, green: 0.98, blue: 0.84, alpha: 1))
        }
        for i in 0..<3 {
            rounded(NSRect(x: xs[i], y: y, width: widths[i], height: 98), 14,
                active ? NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.40, alpha: 1) : NSColor.white.withAlphaComponent(y == 676 ? 0.78 : 0.30))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let path = "\(output)/icon_\(points)x\(points)\(suffix).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
