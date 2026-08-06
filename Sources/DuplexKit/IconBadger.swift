import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum IconBadgerError: Error {
    case unreadableImage(URL)
    case encodingFailed
}

public enum IconBadger {
    static func nsColor(_ color: BadgeColor) -> NSColor {
        switch color {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        }
    }

    /// Renders `image`'s best available representation into a fresh `side`x`side` canvas.
    ///
    /// `NSWorkspace.shared.icon(forFile:)` returns an `NSImage` whose reported `.size` is
    /// often a small legacy size (e.g. 32x32) even when a much larger representation (e.g.
    /// 1024x1024) is embedded. Compositing directly against that image use its small
    /// `.size` as the drawing canvas, so any badge (and the final .icns) ends up rendered
    /// from the low-res representation and upscaled. Drawing into an explicit 1024x1024
    /// rect forces AppKit to pick the highest-quality representation for that target size.
    public static func normalizedIcon(_ image: NSImage, side: CGFloat = 1024) -> NSImage {
        let result = NSImage(size: NSSize(width: side, height: side))
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    public static func badged(_ source: NSImage, color: BadgeColor) -> NSImage {
        let size = source.size.width > 0 ? source.size : NSSize(width: 512, height: 512)
        let result = NSImage(size: size)
        result.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))

        let diameter = size.width * 0.38
        let margin = size.width * 0.04
        // AppKit origin is bottom-left; "bottom-right corner" of the visible icon:
        let badgeRect = NSRect(
            x: size.width - diameter - margin,
            y: margin,
            width: diameter,
            height: diameter)

        let circle = NSBezierPath(ovalIn: badgeRect)
        nsColor(color).setFill()
        circle.fill()
        NSColor.white.setStroke()
        circle.lineWidth = size.width * 0.02
        circle.stroke()

        result.unlockFocus()
        return result
    }

    public static func loadImage(at url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0 else {
            throw IconBadgerError.unreadableImage(url)
        }
        return image
    }

    /// `iconutil`'s iconset file names, each mapped to the pixel size that fills it.
    /// (`icon_16x16@2x.png` is filled by the same 32px render as `icon_32x32.png`, etc.)
    private static let iconsetSlots: [(name: String, side: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    /// Writes `image` out as a multi-resolution .icns, up to a genuine 1024x1024 ("Retina
    /// 512pt@2x") representation.
    ///
    /// This goes through a temporary .iconset directory + the `iconutil` command-line tool
    /// rather than `CGImageDestination`'s icns encoder directly: on current macOS,
    /// `CGImageDestinationAddImage`/`Finalize` silently drops the 64px and 1024px
    /// representations (`finalize` still reports success) instead of writing the modern
    /// `icp6`/`ic10` icon types, so any .icns produced that way tops out at 512px and looks
    /// blurry at large sizes (e.g. Finder icon view, Retina Dock). `iconutil` writes those
    /// slots correctly.
    public static func writeICNS(_ image: NSImage, to url: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("duplex-iconbadger-\(UUID().uuidString)")
        let iconset = workDir.appendingPathComponent("icon.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var renderedBySide: [Int: Data] = [:]
        for slot in iconsetSlots {
            let data: Data
            if let cached = renderedBySide[slot.side] {
                data = cached
            } else {
                guard let cg = renderCGImage(image, side: slot.side),
                      let rendered = pngData(for: cg)
                else { throw IconBadgerError.encodingFailed }
                renderedBySide[slot.side] = rendered
                data = rendered
            }
            try data.write(to: iconset.appendingPathComponent(slot.name))
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0, fm.fileExists(atPath: url.path) else { throw IconBadgerError.encodingFailed }
    }

    private static func pngData(for cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    private static func renderCGImage(_ image: NSImage, side: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
