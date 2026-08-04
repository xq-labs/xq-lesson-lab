#!/usr/bin/env swift
// Draws the DMG install-window background (660×400 pt, matching the website's
// light "paper" theme — Finder always renders icon labels in black over a
// background picture, so the backdrop must stay light for them to read) and
// emits bg.png + bg@2x.png + a combined HiDPI bg.tiff into the
// directory given as arg 1. make-release.sh points the Finder icon-view
// background at the tiff so it stays crisp on retina displays.
//
//   swift scripts/make-dmg-background.swift <outputDir>
//
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let W: CGFloat = 660, H: CGFloat = 400

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: a)
}

func drawText(_ s: String, center: CGPoint, size: CGFloat,
              weight: NSFont.Weight, color: CGColor, tracking: CGFloat = 0,
              in ctx: CGContext) {
    let attr = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color)!,
        .kern: tracking,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: center.x - b.width / 2, y: center.y - b.height / 2)
    CTLineDraw(line, ctx)
}

func render(scale: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)

    // Base + the website's halo: a blue glow up top, a whisper of amber left.
    ctx.setFillColor(hex(0xFBF9F6))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let blue = CGGradient(colorsSpace: space,
                          colors: [hex(0x3E68CE, 0.10), hex(0x3E68CE, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(blue, startCenter: CGPoint(x: W / 2, y: H + 60), startRadius: 0,
                           endCenter: CGPoint(x: W / 2, y: H + 60), endRadius: 430, options: [])
    let amber = CGGradient(colorsSpace: space,
                           colors: [hex(0xD6863A, 0.07), hex(0xD6863A, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(amber, startCenter: CGPoint(x: W * 0.22, y: H * 0.8), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.22, y: H * 0.8), endRadius: 300, options: [])

    // Soft landing pads behind the two icon slots (Finder centers the icons
    // at x=165 and x=495, y=185 from the top → CG y = 215). The pad is taller
    // than it is wide so it also clears the icon's label: at icon size 110 the
    // 13pt name sits around y=252 from the top, so the pad runs from y=112 to
    // y=280 (CG y 120…288) and the text lands inside it instead of straddling
    // the bottom edge.
    for x: CGFloat in [165, 495] {
        let pad = CGRect(x: x - 76, y: 120, width: 152, height: 168)
        let path = CGPath(roundedRect: pad, cornerWidth: 36, cornerHeight: 36, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(hex(0x1F1E1A, 0.04))
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(hex(0x1F1E1A, 0.08))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    // Arrow between the pads.
    ctx.setStrokeColor(hex(0x6E6B62, 0.9))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 262, y: 215))
    ctx.addLine(to: CGPoint(x: 392, y: 215))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 377, y: 228))
    ctx.addLine(to: CGPoint(x: 394, y: 215))
    ctx.addLine(to: CGPoint(x: 377, y: 202))
    ctx.strokePath()

    // Wordmark up top, quiet install hint down below.
    drawText("XQ Lesson Lab", center: CGPoint(x: W / 2, y: 352), size: 17,
             weight: .semibold, color: hex(0x1F1E1A, 0.95), in: ctx)
    drawText("PRIVATE AI PLANNING FOR TEACHERS", center: CGPoint(x: W / 2, y: 330),
             size: 9.5, weight: .medium, color: hex(0x6E6B62, 0.95), tracking: 1.6, in: ctx)
    drawText("Drag to install — runs 100% on your Mac", center: CGPoint(x: W / 2, y: 46),
             size: 12.5, weight: .regular, color: hex(0x6E6B62, 0.95), in: ctx)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String, pointSize: CGSize) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = pointSize  // stamps DPI so tiffutil pairs 1x/2x correctly
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

let size = CGSize(width: W, height: H)
writePNG(render(scale: 1), to: "\(outDir)/bg.png", pointSize: size)
writePNG(render(scale: 2), to: "\(outDir)/bg@2x.png", pointSize: size)

let tiff = Process()
tiff.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiff.arguments = ["-cathidpicheck", "\(outDir)/bg.png", "\(outDir)/bg@2x.png",
                  "-out", "\(outDir)/bg.tiff"]
try! tiff.run()
tiff.waitUntilExit()
guard tiff.terminationStatus == 0 else {
    fputs("tiffutil failed\n", stderr)
    exit(1)
}
print("wrote \(outDir)/bg.tiff (660×400 @1x/@2x)")
