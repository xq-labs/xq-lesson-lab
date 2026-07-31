#!/usr/bin/env swift
// Draws the Lesson Lab app icon with CoreGraphics and emits an .icns (plus a
// 1024px preview PNG). Vector at every size — each iconset entry is rendered
// fresh rather than downsampled, so the 16pt version stays crisp.
//
//   swift scripts/make-icon.swift [concept] [outputDir]
//     concept: book (default, shipped) | flask | ink
//
import AppKit

// MARK: - Small helpers

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space,
               colors: stops.map { hex($0.0) } as CFArray,
               locations: stops.map { $0.1 })!
}

/// Apple-style continuous rounded square (superellipse, n = 5).
func squircle(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let (a, b) = (rect.width / 2, rect.height / 2)
    let steps = 900
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let (ct, st) = (cos(t), sin(t))
        let x = rect.midX + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// Four-point "sparkle" star with concave sides.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let w = r * 0.26
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
    p.closeSubpath()
    return p
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) {
        setFillColor(color); addPath(path); fillPath()
    }
    func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        setStrokeColor(color); setLineWidth(width)
        setLineCap(.round); setLineJoin(.round)
        addPath(path); strokePath()
    }
    func fillGradient(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
}

// MARK: - Shared geometry (1024pt canvas, top-left origin)

let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
/// Apple's icon grid: an 824pt content square centered in the 1024pt canvas.
/// macOS 26 masks this into its own Liquid Glass container, so the artwork
/// keeps the classic margins and the system supplies the glass edge.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)

let cream = hex(0xFBF8F1)

/// Erlenmeyer flask, drawn along the stroke centerline.
func flaskBody() -> CGPath {
    let p = CGMutablePath()
    let neckL: CGFloat = 464, neckR: CGFloat = 560
    let shoulderY: CGFloat = 452, baseY: CGFloat = 768, corner: CGFloat = 48
    p.move(to: CGPoint(x: neckL, y: 300))
    p.addLine(to: CGPoint(x: neckL, y: shoulderY))
    p.addArc(tangent1End: CGPoint(x: 302, y: baseY), tangent2End: CGPoint(x: 722, y: baseY), radius: corner)
    p.addArc(tangent1End: CGPoint(x: 722, y: baseY), tangent2End: CGPoint(x: neckR, y: shoulderY), radius: corner)
    p.addLine(to: CGPoint(x: neckR, y: shoulderY))
    p.addLine(to: CGPoint(x: neckR, y: 300))
    return p
}

/// Liquid with a wavy surface, filling the flask from `surfaceY` down.
func liquid(surfaceY y: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 240, y: y))
    p.addCurve(to: CGPoint(x: 512, y: y - 4),
               control1: CGPoint(x: 330, y: y - 34), control2: CGPoint(x: 424, y: y + 26))
    p.addCurve(to: CGPoint(x: 784, y: y - 10),
               control1: CGPoint(x: 600, y: y - 34), control2: CGPoint(x: 694, y: y + 20))
    p.addLine(to: CGPoint(x: 784, y: 860))
    p.addLine(to: CGPoint(x: 240, y: 860))
    p.closeSubpath()
    return p
}

// MARK: - Concepts

func drawFlask(_ ctx: CGContext) {
    let plateShape = squircle(plate)
    ctx.fillGradient(plateShape, gradient([(0x8AA2F5, 0), (0x4E62C8, 0.52), (0x2A2F7E, 1)]),
                     from: CGPoint(x: 180, y: 100), to: CGPoint(x: 860, y: 924))

    // Soft light from the top-left, and a hairline rim for definition.
    ctx.saveGState(); ctx.addPath(plateShape); ctx.clip()
    ctx.drawRadialGradient(CGGradient(colorsSpace: space,
                                      colors: [hex(0xFFFFFF, 0.30), hex(0xFFFFFF, 0)] as CFArray,
                                      locations: [0, 1])!,
                           startCenter: CGPoint(x: 380, y: 200), startRadius: 0,
                           endCenter: CGPoint(x: 380, y: 200), endRadius: 640, options: [])
    ctx.restoreGState()
    ctx.stroke(plateShape, hex(0xFFFFFF, 0.16), 3)

    let body = flaskBody()

    // Liquid sits inside the body outline; the cream stroke drawn afterwards
    // trims it back to the glass wall.
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.fillGradient(liquid(surfaceY: 604), gradient([(0xFFC978, 0), (0xF08A4B, 1)]),
                     from: CGPoint(x: 300, y: 570), to: CGPoint(x: 700, y: 800))
    ctx.restoreGState()

    // Glass gleam down the left wall, clipped to the body.
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    let gleam = CGMutablePath()
    gleam.move(to: CGPoint(x: 496, y: 486))
    gleam.addLine(to: CGPoint(x: 398, y: 700))
    ctx.stroke(gleam, hex(0xFFFFFF, 0.22), 20)
    ctx.restoreGState()

    ctx.stroke(body, cream, 38)

    // Flask lip.
    ctx.fill(CGPath(roundedRect: CGRect(x: 430, y: 268, width: 164, height: 42),
                    cornerWidth: 21, cornerHeight: 21, transform: nil), cream)

    // Bubbles rising out of the mixture.
    for (x, y, r, a) in [(498.0, 546.0, 17.0, 0.95), (556.0, 502.0, 11.0, 0.8), (486.0, 486.0, 8.0, 0.6)] {
        ctx.fill(CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil),
                 hex(0xFFF6E4, a))
    }

    // The idea/AI spark leaving the flask, over a warm bloom.
    ctx.drawRadialGradient(CGGradient(colorsSpace: space,
                                      colors: [hex(0xFFD98A, 0.38), hex(0xFFD98A, 0)] as CFArray,
                                      locations: [0, 1])!,
                           startCenter: CGPoint(x: 676, y: 316), startRadius: 0,
                           endCenter: CGPoint(x: 676, y: 316), endRadius: 150, options: [])
    ctx.fill(sparkle(CGPoint(x: 676, y: 316), 66), hex(0xFFD98A))
    ctx.fill(sparkle(CGPoint(x: 618, y: 226), 30), hex(0xFFF0C8))
    ctx.fill(sparkle(CGPoint(x: 738, y: 216), 20), hex(0xFFF0C8, 0.85))
}

func drawBook(_ ctx: CGContext) {
    let plateShape = squircle(plate)
    ctx.fillGradient(plateShape, gradient([(0x5C7BE8, 0), (0x36499E, 0.55), (0x212A63, 1)]),
                     from: CGPoint(x: 180, y: 100), to: CGPoint(x: 860, y: 924))
    ctx.stroke(plateShape, hex(0xFFFFFF, 0.16), 3)

    // The book sits a little above center so the spark cluster nests into the
    // V of the open pages instead of floating off on its own.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: -10)

    // Cover slab behind the pages, giving the book some thickness.
    let cover = CGMutablePath()
    cover.move(to: CGPoint(x: 512, y: 470))
    cover.addCurve(to: CGPoint(x: 206, y: 424), control1: CGPoint(x: 420, y: 416), control2: CGPoint(x: 304, y: 400))
    cover.addArc(tangent1End: CGPoint(x: 206, y: 764), tangent2End: CGPoint(x: 818, y: 764), radius: 34)
    cover.addArc(tangent1End: CGPoint(x: 818, y: 764), tangent2End: CGPoint(x: 818, y: 424), radius: 34)
    cover.addLine(to: CGPoint(x: 818, y: 424))
    cover.addCurve(to: CGPoint(x: 512, y: 470), control1: CGPoint(x: 720, y: 400), control2: CGPoint(x: 604, y: 416))
    cover.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 34, color: hex(0x0B1030, 0.45))
    ctx.fill(cover, hex(0x0E1440))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Page block: a sliver of stacked paper between cover and open pages.
    let block = CGMutablePath()
    block.move(to: CGPoint(x: 512, y: 500))
    block.addCurve(to: CGPoint(x: 228, y: 452), control1: CGPoint(x: 420, y: 448), control2: CGPoint(x: 318, y: 430))
    block.addLine(to: CGPoint(x: 228, y: 716))
    block.addCurve(to: CGPoint(x: 512, y: 758), control1: CGPoint(x: 318, y: 694), control2: CGPoint(x: 420, y: 708))
    block.addCurve(to: CGPoint(x: 796, y: 716), control1: CGPoint(x: 604, y: 708), control2: CGPoint(x: 706, y: 694))
    block.addLine(to: CGPoint(x: 796, y: 452))
    block.addCurve(to: CGPoint(x: 512, y: 500), control1: CGPoint(x: 706, y: 430), control2: CGPoint(x: 604, y: 448))
    block.closeSubpath()
    ctx.fill(block, hex(0xC9C4B4))

    // Two pages splayed from the spine.
    func page(mirrored: Bool) -> CGPath {
        let p = CGMutablePath()
        let s: CGFloat = mirrored ? -1 : 1
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + s * (x - 512), y: y) }
        p.move(to: pt(512, 448))
        p.addCurve(to: pt(238, 402), control1: pt(422, 396), control2: pt(318, 380))
        p.addLine(to: pt(238, 686))
        p.addCurve(to: pt(512, 728), control1: pt(324, 664), control2: pt(424, 678))
        p.closeSubpath()
        return p
    }
    ctx.fillGradient(page(mirrored: false), gradient([(0xFFFDF8, 0), (0xE8E2D2, 1)]),
                     from: CGPoint(x: 240, y: 400), to: CGPoint(x: 512, y: 730))
    ctx.fillGradient(page(mirrored: true), gradient([(0xFFFDF8, 0), (0xE8E2D2, 1)]),
                     from: CGPoint(x: 784, y: 400), to: CGPoint(x: 512, y: 730))

    // Ruled lines to read as a lesson rather than a blank book.
    ctx.setLineCap(.round)
    for (i, y) in [470.0, 528.0, 586.0].enumerated() {
        let inset = CGFloat(i) * 14
        for s in [-1.0, 1.0] as [CGFloat] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 512 + s * (78 + inset * 0.2), y: y + 18))
            p.addCurve(to: CGPoint(x: 512 + s * (250 - inset), y: y - 6),
                       control1: CGPoint(x: 512 + s * 150, y: y + 6),
                       control2: CGPoint(x: 512 + s * 200, y: y - 2))
            ctx.stroke(p, hex(0x9AA6C9, 0.55), 13)
        }
    }
    ctx.restoreGState()

    // Spark cluster, dropped into the V where the pages meet.
    ctx.drawRadialGradient(CGGradient(colorsSpace: space,
                                      colors: [hex(0xFFD98A, 0.34), hex(0xFFD98A, 0)] as CFArray,
                                      locations: [0, 1])!,
                           startCenter: CGPoint(x: 512, y: 314), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 314), endRadius: 190, options: [])
    ctx.fill(sparkle(CGPoint(x: 512, y: 314), 84), hex(0xFFD98A))
    ctx.fill(sparkle(CGPoint(x: 652, y: 258), 34), hex(0xFFF0C8))
    ctx.fill(sparkle(CGPoint(x: 380, y: 272), 24), hex(0xFFF0C8, 0.85))
}

func drawInk(_ ctx: CGContext) {
    let plateShape = squircle(plate)
    ctx.fillGradient(plateShape, gradient([(0x2A2A27, 0), (0x1A1A19, 0.55), (0x121211, 1)]),
                     from: CGPoint(x: 180, y: 100), to: CGPoint(x: 860, y: 924))
    ctx.stroke(plateShape, hex(0xFFFFFF, 0.10), 3)

    let body = flaskBody()
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.fillGradient(liquid(surfaceY: 596), gradient([(0x8FB0FF, 0), (0x3E68CE, 1)]),
                     from: CGPoint(x: 300, y: 560), to: CGPoint(x: 700, y: 800))
    ctx.restoreGState()

    ctx.stroke(body, cream, 34)
    ctx.fill(CGPath(roundedRect: CGRect(x: 434, y: 270, width: 156, height: 38),
                    cornerWidth: 19, cornerHeight: 19, transform: nil), cream)

    for (x, y, r, a) in [(500.0, 540.0, 15.0, 0.9), (556.0, 498.0, 10.0, 0.7)] {
        ctx.fill(CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil),
                 hex(0xBFD2FF, a))
    }
    ctx.fill(sparkle(CGPoint(x: 672, y: 320), 58), hex(0x9DB7F5))
    ctx.fill(sparkle(CGPoint(x: 616, y: 238), 26), hex(0xD8E2FF, 0.9))
}

// MARK: - Render

let positional = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let concept = positional.first ?? "book"
let outDir = positional.count > 1 ? positional[positional.startIndex + 1] : "."
let draw: (CGContext) -> Void = {
    switch concept {
    case "flask": return drawFlask
    case "ink": return drawInk
    default: return drawBook
    }
}()

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    // Flip to a top-left origin and scale the 1024pt design down to `size`.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / canvas.width, y: -CGFloat(size) / canvas.height)
    draw(ctx)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default

// Web export: the same artwork as PNGs for the landing page. The 1024 is the
// link-preview image, so it gets an opaque backdrop — social clients composite
// transparency onto anything.
if CommandLine.arguments.contains("--web") {
    for (size, name) in [(32, "favicon-32.png"), (180, "apple-touch-icon.png"), (512, "icon-512.png")] {
        write(render(size: size), to: "\(outDir)/\(name)")
    }
    let s = 1024
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(hex(0xFBF9F6))          // matches the site's --bg
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.draw(render(size: s), in: CGRect(x: 0, y: 0, width: s, height: s))
    write(ctx.makeImage()!, to: "\(outDir)/og-image.png")
    print("Wrote web icons to \(outDir) (\(concept))")
    exit(0)
}

let iconset = "\(outDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    write(render(size: base), to: "\(iconset)/icon_\(base)x\(base).png")
    write(render(size: base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
write(render(size: 1024), to: "\(outDir)/AppIcon-preview-\(concept).png")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
try? fm.removeItem(atPath: iconset)
print("Wrote \(outDir)/AppIcon.icns (\(concept))")
