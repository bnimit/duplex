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
