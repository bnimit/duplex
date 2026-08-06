// Generates assets/AppIcon.icns for Duplex.
// Run: swift scripts/make-icon.swift
// Design: indigo two-tone squircle (one field, two tones — a "duplex"),
// a ghost app shape behind a solid glass copy in front, wearing the same
// coral badge dot Duplex paints on wrapper icons.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let master: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func draw(in ctx: CGContext) {
    let s = master

    // Squircle plate (Big Sur metrics: 824pt centered on a 1024 canvas).
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Baked ambient shadow, like system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x2A1D86))
    ctx.fillPath()
    ctx.restoreGState()

    // Two-tone field: violet upper-left into deep indigo lower-right.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let field = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x6E5BFF), color(0x2A1D86)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        field,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: [])

    // Faint top light so the plate reads as glass, not flat print.
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0.0)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: s / 2, y: plate.maxY),
        end: CGPoint(x: s / 2, y: plate.maxY - plate.height * 0.45),
        options: [])

    // The duplicate gesture: ghost copy up-left, solid copy down-right.
    let side: CGFloat = 380
    let corner: CGFloat = 86
    let offset: CGFloat = 70

    let rearRect = CGRect(x: s / 2 - side / 2 - offset, y: s / 2 - side / 2 + offset, width: side, height: side)
    ctx.addPath(CGPath(roundedRect: rearRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, 0.32))
    ctx.fillPath()

    let frontRect = CGRect(x: s / 2 - side / 2 + offset, y: s / 2 - side / 2 - offset, width: side, height: side)
    let frontPath = CGPath(roundedRect: frontRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
    ctx.addPath(frontPath)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(frontPath)
    ctx.clip()
    let glass = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF), color(0xE7E3FF)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        glass,
        start: CGPoint(x: s / 2, y: frontRect.maxY),
        end: CGPoint(x: s / 2, y: frontRect.minY),
        options: [])
    ctx.restoreGState()

    // The badge dot — the same mark Duplex paints on every wrapper icon.
    let badgeCenter = CGPoint(x: frontRect.maxX - 24, y: frontRect.minY + 24)
    let badgeRadius: CGFloat = 62
    let badgeRect = CGRect(
        x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2, height: badgeRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: badgeRect)
    ctx.clip()
    let coral = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFF8A70), color(0xF0503C)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        coral,
        start: CGPoint(x: badgeCenter.x, y: badgeRect.maxY),
        end: CGPoint(x: badgeCenter.x, y: badgeRect.minY),
        options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: badgeRect.insetBy(dx: 7, dy: 7))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(14)
    ctx.strokePath()

    ctx.restoreGState()
}

func renderMaster() -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(master), height: Int(master),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(in: ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, side: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let scaled = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, scaled, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let image = renderMaster()
let slots: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, side) in slots {
    writePNG(image, side: side, to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote assets/AppIcon.icns")
