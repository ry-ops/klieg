// Draws the Klieg app icon (a stage light on three agents) and writes an .iconset folder.
// usage: swift scripts/make-icon.swift OUTPUT.iconset [preview.png]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()

    // Rounded-square stage: near-black with a cool blue tint toward the bottom.
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let body = CGPath(roundedRect: rect, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(body); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(body); ctx.clip()
    let stage = CGGradient(colorsSpace: rgb, colors: [NSColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1).cgColor,
                                                     NSColor(red: 0.07, green: 0.11, blue: 0.22, alpha: 1).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(stage, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

    // The beam: a warm cone from the lamp (top left) down to a pool on the floor.
    let lamp = CGPoint(x: s * 0.30, y: s * 0.80)
    let pool = CGPoint(x: s * 0.56, y: s * 0.30)
    let poolW = s * 0.50, poolH = s * 0.15
    let cone = CGMutablePath()
    // The beam leaves the lens, which sits at the lamp head's front edge (rotated with the head below).
    let lens = CGPoint(x: lamp.x + s * 0.058, y: lamp.y - s * 0.054)
    cone.move(to: CGPoint(x: lens.x - s * 0.028, y: lens.y - s * 0.03))
    cone.addLine(to: CGPoint(x: pool.x - poolW / 2, y: pool.y))
    cone.addLine(to: CGPoint(x: pool.x + poolW / 2, y: pool.y))
    cone.addLine(to: CGPoint(x: lens.x + s * 0.03, y: lens.y + s * 0.026))
    cone.closeSubpath()
    ctx.saveGState()
    ctx.addPath(cone); ctx.clip()
    let beam = CGGradient(colorsSpace: rgb, colors: [NSColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 0.85).cgColor,
                                                    NSColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 0.18).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(beam, start: lens, end: pool, options: [])
    ctx.restoreGState()

    // The pool of light.
    ctx.saveGState()
    let poolRect = CGRect(x: pool.x - poolW / 2, y: pool.y - poolH / 2, width: poolW, height: poolH)
    ctx.addEllipse(in: poolRect); ctx.clip()
    let glow = CGGradient(colorsSpace: rgb, colors: [NSColor(red: 1.0, green: 0.93, blue: 0.72, alpha: 1).cgColor,
                                                    NSColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 0.15).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: pool, startRadius: 0, endCenter: pool, endRadius: poolW / 2, options: [])
    ctx.restoreGState()

    // Three agents standing in the light (the middle one taller, in the accent color).
    func agent(_ x: CGFloat, _ h: CGFloat, _ color: NSColor) {
        let w = s * 0.075
        let base = pool.y - s * 0.005
        let figure = CGPath(roundedRect: CGRect(x: x - w / 2, y: base, width: w, height: h),
                            cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        ctx.addPath(figure); ctx.setFillColor(color.cgColor); ctx.fillPath()
        let head = s * 0.062
        ctx.addEllipse(in: CGRect(x: x - head / 2, y: base + h + s * 0.015, width: head, height: head))
        ctx.fillPath()
    }
    let dim = NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
    agent(pool.x - s * 0.13, s * 0.11, dim)
    agent(pool.x + s * 0.13, s * 0.11, dim)
    agent(pool.x, s * 0.15, NSColor(red: 0.24, green: 0.55, blue: 1.0, alpha: 1))

    // The lamp head.
    ctx.saveGState()
    ctx.translateBy(x: lamp.x, y: lamp.y)
    ctx.rotate(by: -0.75)
    let head = CGPath(roundedRect: CGRect(x: -s * 0.07, y: -s * 0.045, width: s * 0.15, height: s * 0.09),
                      cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
    ctx.addPath(head); ctx.setFillColor(NSColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1).cgColor); ctx.fillPath()
    ctx.addRect(CGRect(x: s * 0.07, y: -s * 0.04, width: s * 0.018, height: s * 0.08))
    ctx.setFillColor(NSColor(red: 1.0, green: 0.92, blue: 0.70, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 { try! draw(512).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
