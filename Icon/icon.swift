// Kenos app icon — black centre inside one soft, blurred ring of light.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let plate = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.223
    let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)
    srgb(0.02, 0.015, 0.015).setFill()
    platePath.fill()

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    platePath.addClip()
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let space = CGColorSpaceCreateDeviceRGB()
    let cx = size * 0.5
    let cy = size * 0.5
    let holeR = size * 0.16
    // Ring centreline and how far the blur spreads.
    let midR = size * 0.275
    let blur = size * 0.085

    // One continuous ring: many translucent strokes of decreasing weight,
    // so it reads as a single soft glow — no arcs, bands, or lobes.
    let steps = max(24, Int(size / 4))
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1) // 0…1 across the band
        let r = midR - blur + blur * 2 * t
        guard r > 0 else { continue }
        // Gaussian-ish falloff from the centreline.
        let d = abs(t - 0.5) * 2 // 0 at mid, 1 at edges
        let envelope = exp(-d * d * 3.2)
        // Warm core → deeper orange at the fringes; same all the way around.
        let hot = envelope
        let red: CGFloat = 1.0
        let green: CGFloat = 0.55 + 0.35 * hot
        let blue: CGFloat = 0.10 + 0.35 * hot
        let alpha = 0.55 * envelope
        let path = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        path.lineWidth = max(0.8, blur * 0.22)
        srgb(red, green, blue, alpha).setStroke()
        path.stroke()
    }

    // Soft outer haze — still a full circle.
    do {
        var comps: [CGFloat] = [
            1.0, 0.45, 0.08, 0.20,
            0.6, 0.15, 0.02, 0.06,
            0.1, 0.02, 0.0, 0,
        ]
        var locs: [CGFloat] = [0, 0.55, 1]
        if let g = CGGradient(colorSpace: space, colorComponents: &comps, locations: &locs, count: 3) {
            ctx.drawRadialGradient(
                g,
                startCenter: CGPoint(x: cx, y: cy), startRadius: holeR,
                endCenter: CGPoint(x: cx, y: cy), endRadius: midR + blur * 1.6,
                options: []
            )
        }
    }

    // The center — clean black disc, no highlights inside.
    srgb(0, 0, 0).setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - holeR, y: cy - holeR, width: holeR * 2, height: holeR * 2)).fill()

    // Gentle fade where the ring meets the hole (still circular, no sections).
    do {
        var comps: [CGFloat] = [
            0, 0, 0, 1,
            0, 0, 0, 0.4,
            0, 0, 0, 0,
        ]
        var locs: [CGFloat] = [0, 0.65, 1]
        if let g = CGGradient(colorSpace: space, colorComponents: &comps, locations: &locs, count: 3) {
            ctx.drawRadialGradient(
                g,
                startCenter: CGPoint(x: cx, y: cy), startRadius: holeR * 0.9,
                endCenter: CGPoint(x: cx, y: cy), endRadius: holeR * 1.08,
                options: []
            )
        }
    }

    ctx.restoreGState()
    return image
}

func raster(_ image: NSImage, pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height).fill()
    image.draw(in: NSRect(origin: .zero, size: image.size),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] as [(Int,Int)] {
    let logical = CGFloat(size)
    let image = drawIcon(size: logical)
    guard let rep = raster(image, pixels: size * scale),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try? png.write(to: out.appendingPathComponent(name))
}

print("wrote \(out.path)")
