import XCTest
import AppKit
@testable import DuplexKit

final class IconBadgerTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func solidImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.unlockFocus()
        return image
    }

    func testBadgedChangesBottomRightPixel() throws {
        let plain = solidImage(size: 512)
        let badged = IconBadger.badged(plain, color: .red)
        XCTAssertEqual(badged.size, plain.size)

        guard let tiff = badged.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("no bitmap")
        }
        // Badge is drawn in the bottom-right quadrant; that pixel must no longer be white.
        let px = rep.colorAt(x: rep.pixelsWide - rep.pixelsWide / 6, y: rep.pixelsHigh - rep.pixelsHigh / 6)
        XCTAssertNotNil(px)
        XCTAssertLessThan(px!.greenComponent, 0.9, "badge should have painted over the white background")
    }

    /// Builds an `NSImage` that mimics what `NSWorkspace.shared.icon(forFile:)` actually
    /// returns: a small nominal `.size` (32x32) with a much larger representation (1024x1024)
    /// also embedded, and the two reps rendered in visibly different colors so a test can
    /// tell which one got used.
    private func mismatchedSizeIcon() -> NSImage {
        func rep(side: Int, color: NSColor) -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            color.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }

        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(rep(side: 32, color: .red))
        image.addRepresentation(rep(side: 1024, color: .blue))
        return image
    }

    /// Regression test for the bug `IconBadger.normalizedIcon` fixes: `NSWorkspace`-style
    /// icons report a small nominal `.size` even when a much larger representation is
    /// embedded. Compositing directly against that `.size` (the old behavior) renders from
    /// the low-res rep; normalizing into an explicit 1024px canvas first must pick the
    /// high-res rep instead. This exercises the exact call path `WrapperGenerator` uses for
    /// `.badge`: `normalizedIcon` then `badged`.
    func testNormalizedIconUsesHighResRepresentationNotNominalSize() throws {
        let mismatched = mismatchedSizeIcon()
        let normalized = IconBadger.normalizedIcon(mismatched)
        let badged = IconBadger.badged(normalized, color: .red)

        guard let tiff = badged.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("no bitmap")
        }
        // Sample near the top-left, away from the badge (which is drawn bottom-right).
        guard let px = rep.colorAt(x: 5, y: 5) else { return XCTFail("no pixel color") }
        XCTAssertGreaterThan(px.blueComponent, 0.5, "should be rendered from the 1024px BLUE rep, not the 32px RED rep")
        XCTAssertLessThan(px.redComponent, 0.5, "should not still be showing the low-res RED rep")
    }

    func testWriteICNSProducesLoadableFile() throws {
        let out = tmp.appendingPathComponent("icon.icns")
        try IconBadger.writeICNS(solidImage(size: 512), to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertNotNil(NSImage(contentsOf: out))
    }

    func testLoadImageThrowsForGarbage() throws {
        let bad = tmp.appendingPathComponent("junk.png")
        try Data("not an image".utf8).write(to: bad)
        XCTAssertThrowsError(try IconBadger.loadImage(at: bad))
    }
}
