// Draws the app icon (viewfinder corners around a camera) and writes
// app/AppIcon.icns. Run from the repo root after changing the design:
//
//   swift app/make-icon.swift
//
// Drawn from scratch rather than with SF Symbols, whose license doesn't allow
// use in app icons.

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// Draws on a 1024×1024 canvas (y up), following the macOS icon grid:
/// an 824pt rounded square centred with room for its shadow.
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0xe8492b).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0xff7b58), ending: color(0xde3a1f))!.draw(in: squircle, angle: -90)

    // Soft top sheen.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let ink = NSColor.white
    ink.setStroke()
    ink.setFill()

    // Viewfinder corners.
    let frame = NSRect(x: 252, y: 252, width: 520, height: 520)
    let arm: CGFloat = 138, r: CGFloat = 46
    let corners = NSBezierPath()
    corners.lineWidth = 58
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    for (x, y, dx, dy) in [(frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0),
                           (frame.maxX, frame.minY, -1.0, 1.0), (frame.minX, frame.minY, 1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        corners.move(to: NSPoint(x: x, y: y + dy * arm))
        corners.line(to: NSPoint(x: x, y: y + dy * r))
        corners.curve(to: NSPoint(x: x + dx * r, y: y), controlPoint1: NSPoint(x: x, y: y),
                      controlPoint2: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x + dx * arm, y: y))
    }
    corners.stroke()

    // Camera: body with a viewfinder bump, lens cut out, and a lens highlight.
    let center = NSPoint(x: 512, y: 500)
    // The bump overlaps the body; fill them separately so even-odd only cuts the lens.
    NSBezierPath(roundedRect: NSRect(x: 452, y: 580, width: 120, height: 56), xRadius: 22, yRadius: 22).fill()
    let bodyWithLens = NSBezierPath(roundedRect: NSRect(x: 362, y: 400, width: 300, height: 206), xRadius: 42, yRadius: 42)
    bodyWithLens.append(NSBezierPath(ovalIn: NSRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)))
    bodyWithLens.windingRule = .evenOdd
    bodyWithLens.fill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 36, y: center.y - 36, width: 72, height: 72)).fill()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: URL(fileURLWithPath: "app/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "app/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote app/AppIcon.icns and app/AppIcon-1024.png" : "iconutil failed")
