// Draws the Klieg app icon (a searchlight on a yoke and pedestal) and writes an .iconset folder.
// usage: swift scripts/make-icon.swift OUTPUT.iconset [preview.png]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { NSColor(red: r, green: g, blue: b, alpha: a).cgColor }

// Olive gunmetal, from shadow to highlight.
let metalDark = c(0.17, 0.19, 0.15), metal = c(0.27, 0.30, 0.24), metalLight = c(0.40, 0.43, 0.35), metalEdge = c(0.52, 0.55, 0.46)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()
    func grad(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locs)!
    }
    // Everything below is laid out on a 1000-unit canvas.
    ctx.scaleBy(x: s / 1000, y: s / 1000)

    // --- Rounded-square body: night sky, a little lighter at the top.
    let rect = CGRect(x: 90, y: 90, width: 820, height: 820)
    let body = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: c(0, 0, 0, 0.45))
    ctx.addPath(body); ctx.setFillColor(c(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(grad([c(0.10, 0.13, 0.22), c(0.04, 0.05, 0.09)]), start: CGPoint(x: 0, y: 910), end: CGPoint(x: 0, y: 90), options: [])

    // --- The beam, thrown up and to the left from the lens.
    let lensC = CGPoint(x: 430, y: 560)
    let axis = CGVector(dx: -0.62, dy: 0.785)          // where the light points (up-left)
    let perp = CGVector(dx: axis.dy, dy: -axis.dx)
    let beam = CGMutablePath()
    let far: CGFloat = 900, near: CGFloat = 120, spread: CGFloat = 330
    beam.move(to: CGPoint(x: lensC.x + perp.dx * near, y: lensC.y + perp.dy * near))
    beam.addLine(to: CGPoint(x: lensC.x + axis.dx * far + perp.dx * spread, y: lensC.y + axis.dy * far + perp.dy * spread))
    beam.addLine(to: CGPoint(x: lensC.x + axis.dx * far - perp.dx * spread, y: lensC.y + axis.dy * far - perp.dy * spread))
    beam.addLine(to: CGPoint(x: lensC.x - perp.dx * near, y: lensC.y - perp.dy * near))
    beam.closeSubpath()
    ctx.saveGState()
    ctx.addPath(beam); ctx.clip()
    ctx.drawLinearGradient(grad([c(1, 0.86, 0.52, 0.62), c(1, 0.80, 0.42, 0.18), c(1, 0.78, 0.40, 0.0)], [0, 0.55, 1]),
                           start: lensC, end: CGPoint(x: lensC.x + axis.dx * far, y: lensC.y + axis.dy * far), options: [])
    ctx.restoreGState()

    // --- Pedestal: a wide round base, then a short column.
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect { CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2) }
    // base slab (side, then top)
    ctx.saveGState()
    let slab = CGMutablePath()
    slab.addEllipse(in: ellipse(500, 205, 230, 58))
    slab.addRect(CGRect(x: 270, y: 205, width: 460, height: 44))
    slab.addEllipse(in: ellipse(500, 249, 230, 58))
    ctx.addPath(slab); ctx.clip()
    ctx.drawLinearGradient(grad([metalDark, metal, metalDark]), start: CGPoint(x: 270, y: 0), end: CGPoint(x: 730, y: 0), options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: ellipse(500, 249, 230, 58)); ctx.setFillColor(metalLight); ctx.fillPath()
    ctx.addEllipse(in: ellipse(500, 249, 230, 58)); ctx.setStrokeColor(metalEdge); ctx.setLineWidth(3); ctx.strokePath()
    // ribs on the base
    for i in 0..<6 {
        let a = CGFloat(i) / 6 * .pi + 0.25
        let x = 500 + cos(a) * 200, y = 249 - sin(a) * 50
        ctx.addRect(CGRect(x: x - 9, y: y - 4, width: 18, height: 26)); ctx.setFillColor(metal); ctx.fillPath()
    }
    // column
    ctx.saveGState()
    ctx.addRect(CGRect(x: 438, y: 249, width: 124, height: 70)); ctx.clip()
    ctx.drawLinearGradient(grad([metalDark, metalLight, metalDark]), start: CGPoint(x: 438, y: 0), end: CGPoint(x: 562, y: 0), options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: ellipse(500, 319, 62, 16)); ctx.setFillColor(metalLight); ctx.fillPath()

    // --- Yoke: a U-shaped bracket holding the drum by its sides.
    let yoke = CGMutablePath()
    yoke.move(to: CGPoint(x: 300, y: 330))
    yoke.addLine(to: CGPoint(x: 680, y: 330))
    yoke.addLine(to: CGPoint(x: 718, y: 395))
    yoke.addLine(to: CGPoint(x: 722, y: 600))
    yoke.addLine(to: CGPoint(x: 650, y: 612))
    yoke.addLine(to: CGPoint(x: 640, y: 405))
    yoke.addLine(to: CGPoint(x: 340, y: 405))
    yoke.addLine(to: CGPoint(x: 318, y: 470))
    yoke.addLine(to: CGPoint(x: 248, y: 462))
    yoke.addLine(to: CGPoint(x: 262, y: 390))
    yoke.closeSubpath()
    ctx.saveGState()
    ctx.addPath(yoke); ctx.clip()
    ctx.drawLinearGradient(grad([metal, metalLight, metalDark]), start: CGPoint(x: 300, y: 600), end: CGPoint(x: 700, y: 330), options: [])
    ctx.restoreGState()
    ctx.addPath(yoke); ctx.setStrokeColor(metalDark); ctx.setLineWidth(4); ctx.strokePath()

    // --- The drum: a cylinder whose front faces up-left, built from stacked ellipses back to front.
    let tilt = atan2(axis.dy, axis.dx) - .pi / 2      // rotate ellipses so their face is perpendicular to the axis
    let R: CGFloat = 205, squash: CGFloat = 0.72, depth: CGFloat = 150
    func drumEllipse(at d: CGFloat, radius: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: lensC.x + axis.dx * d, y: lensC.y + axis.dy * d).rotated(by: tilt)
        return CGPath(ellipseIn: CGRect(x: -radius, y: -radius * squash, width: radius * 2, height: radius * 2 * squash), transform: &t)
    }
    // back to front: darker at the back
    let steps = 40
    for i in 0...steps {
        let f = CGFloat(i) / CGFloat(steps)
        let d = -depth + f * depth
        ctx.addPath(drumEllipse(at: d, radius: R * (0.93 + 0.07 * f)))
        let k = 0.55 + 0.45 * f
        ctx.setFillColor(c(0.27 * k, 0.30 * k, 0.24 * k)); ctx.fillPath()
    }
    // side highlight band
    ctx.saveGState()
    ctx.addPath(drumEllipse(at: -depth * 0.35, radius: R * 0.985)); ctx.setStrokeColor(c(0.45, 0.48, 0.39, 0.6)); ctx.setLineWidth(10); ctx.strokePath()
    ctx.restoreGState()
    // trunnion bolts where the yoke meets the drum
    for x in [CGFloat(332), 668] {
        ctx.addEllipse(in: ellipse(x, 560, 34, 34)); ctx.setFillColor(metalDark); ctx.fillPath()
        ctx.addEllipse(in: ellipse(x, 560, 20, 20)); ctx.setFillColor(c(0.78, 0.80, 0.82)); ctx.fillPath()
    }
    // front bezel ring
    ctx.addPath(drumEllipse(at: 4, radius: R)); ctx.setFillColor(metalLight); ctx.fillPath()
    ctx.addPath(drumEllipse(at: 4, radius: R)); ctx.setStrokeColor(metalEdge); ctx.setLineWidth(6); ctx.strokePath()

    // --- The lens: glowing glass, vertical ribs, a cross and a hub.
    let lens = drumEllipse(at: 8, radius: R * 0.86)
    ctx.saveGState()
    ctx.addPath(lens); ctx.clip()
    ctx.drawRadialGradient(grad([c(1, 1, 0.97), c(1, 0.93, 0.74), c(0.95, 0.78, 0.48)], [0, 0.55, 1]),
                           startCenter: CGPoint(x: lensC.x - 30, y: lensC.y + 40), startRadius: 0,
                           endCenter: lensC, endRadius: R * 0.95, options: [.drawsAfterEndLocation])
    // vertical ribs in the glass, as on a real searchlight
    ctx.setStrokeColor(c(0.80, 0.66, 0.42, 0.5)); ctx.setLineWidth(5)
    var x: CGFloat = lensC.x - R
    while x <= lensC.x + R { ctx.move(to: CGPoint(x: x, y: lensC.y - R)); ctx.addLine(to: CGPoint(x: x, y: lensC.y + R)); x += 24 }
    ctx.strokePath()
    // cross bars follow the lens's own frame
    ctx.translateBy(x: lensC.x + axis.dx * 8, y: lensC.y + axis.dy * 8)
    ctx.rotate(by: tilt)
    // cross bars and hub
    ctx.setStrokeColor(c(0.30, 0.32, 0.27)); ctx.setLineWidth(11)
    ctx.move(to: CGPoint(x: -R, y: 0)); ctx.addLine(to: CGPoint(x: R, y: 0))
    ctx.move(to: CGPoint(x: 0, y: -R)); ctx.addLine(to: CGPoint(x: 0, y: R))
    ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: -20, y: -20 * squash, width: 40, height: 40 * squash)); ctx.setFillColor(c(0.30, 0.32, 0.27)); ctx.fillPath()
    ctx.restoreGState()
    // glass sheen
    ctx.saveGState()
    ctx.addPath(lens); ctx.clip()
    ctx.drawRadialGradient(grad([c(1, 1, 1, 0.55), c(1, 1, 1, 0)]),
                           startCenter: CGPoint(x: lensC.x - 70, y: lensC.y + 70), startRadius: 0,
                           endCenter: CGPoint(x: lensC.x - 70, y: lensC.y + 70), endRadius: 110, options: [])
    ctx.restoreGState()
    ctx.addPath(lens); ctx.setStrokeColor(metalDark); ctx.setLineWidth(5); ctx.strokePath()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 { try! draw(512).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
