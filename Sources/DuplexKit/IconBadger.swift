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

    public static func writeICNS(_ image: NSImage, to url: URL) throws {
        let sizes: [Int] = [16, 32, 128, 256, 512]
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.icns.identifier as CFString, sizes.count, nil)
        else { throw IconBadgerError.encodingFailed }

        for side in sizes {
            guard let cg = renderCGImage(image, side: side) else { throw IconBadgerError.encodingFailed }
            CGImageDestinationAddImage(dest, cg, nil)
        }
        guard CGImageDestinationFinalize(dest) else { throw IconBadgerError.encodingFailed }
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
