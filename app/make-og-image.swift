// Draws the 1200×630 link preview used by the website (Open Graph / Twitter)
// and writes docs/og-image.png. Run from the repo root after changing the design:
//
//   swift app/make-og-image.swift

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let size = NSSize(width: 1200, height: 630)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

color(0xf6f1e9).setFill()
NSRect(origin: .zero, size: size).fill()

let icon = NSImage(contentsOfFile: "app/AppIcon-1024.png")!
icon.draw(in: NSRect(x: 64, y: 395, width: 180, height: 180))

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: -size * 0.03,
    ]
    NSAttributedString(string: string, attributes: attrs).draw(at: point)
}

text("Give Me Back My Screenshot", size: 38, weight: .semibold, color: color(0x5d554b), at: NSPoint(x: 268, y: 462))
text("The thumbnail vanished.", size: 84, weight: .heavy, color: color(0x1b1712), at: NSPoint(x: 72, y: 250))
text("Your screenshot didn't.", size: 84, weight: .heavy, color: color(0xe8492b), at: NSPoint(x: 72, y: 150))
text("Every Mac screenshot on your clipboard automatically · Free & open source",
     size: 30, weight: .regular, color: color(0x5d554b), at: NSPoint(x: 76, y: 70))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/og-image.png"))
print("Wrote docs/og-image.png")
