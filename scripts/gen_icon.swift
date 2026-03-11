import Cocoa

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let iconsetPath = "/tmp/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (px, name) in sizes {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Background: dark rounded rect
    let corner = s * 0.22
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: corner, yRadius: corner)
    NSColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1).setFill() // #18181b
    bgPath.fill()

    // Subtle border
    NSColor(white: 1, alpha: 0.08).setStroke()
    bgPath.lineWidth = s * 0.01
    bgPath.stroke()

    // Diamond shape (◆) with gradient
    let diamondSize = s * 0.48
    let cx = s / 2, cy = s / 2
    let diamond = NSBezierPath()
    diamond.move(to: NSPoint(x: cx, y: cy + diamondSize / 2))       // top
    diamond.line(to: NSPoint(x: cx + diamondSize / 2, y: cy))       // right
    diamond.line(to: NSPoint(x: cx, y: cy - diamondSize / 2))       // bottom
    diamond.line(to: NSPoint(x: cx - diamondSize / 2, y: cy))       // left
    diamond.close()

    // Purple gradient fill
    ctx.saveGState()
    diamond.addClip()
    let colors = [
        NSColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1).cgColor, // #7c3aed
        NSColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 1).cgColor, // #a78bfa
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: cx - diamondSize/2, y: cy + diamondSize/2),
        end: CGPoint(x: cx + diamondSize/2, y: cy - diamondSize/2),
        options: [])
    ctx.restoreGState()

    // Glow effect
    let glowDiamond = NSBezierPath()
    let gs = diamondSize * 1.15
    glowDiamond.move(to: NSPoint(x: cx, y: cy + gs / 2))
    glowDiamond.line(to: NSPoint(x: cx + gs / 2, y: cy))
    glowDiamond.line(to: NSPoint(x: cx, y: cy - gs / 2))
    glowDiamond.line(to: NSPoint(x: cx - gs / 2, y: cy))
    glowDiamond.close()
    NSColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 0.15).setFill()
    glowDiamond.fill()

    img.unlockFocus()

    // Save as PNG
    let tiffData = img.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: tiffData)!
    let pngData = bitmap.representation(using: .png, properties: [:])!
    try! pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}

print("Iconset generated")
