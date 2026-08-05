import XCTest
import AppKit
@testable import DuplyKit

final class WrapperGeneratorTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeSpec() throws -> InstanceSpec {
        let app = try FixtureFactory.makeFakeApp(
            named: "Fake", bundleID: "com.x.fake", electron: true, schemes: ["fake"], in: tmp)
        return InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
    }

    // /bin/ls is a real Mach-O so codesign of the wrapper succeeds in tests.
    private var generator: WrapperGenerator { WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls")) }

    func testGeneratesCompleteBundle() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .badge(.blue), outputDir: out)

        XCTAssertEqual(wrapper.lastPathComponent, "Fake Work.app")
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/PkgInfo").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Resources/icon.icns").path))

        let exec = wrapper.appendingPathComponent("Contents/MacOS/duply-launcher")
        XCTAssertTrue(fm.isExecutableFile(atPath: exec.path))

        let data = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.duply.fake-work")
        XCTAssertEqual(plist[DuplyPlistKey.instanceSlug] as? String, "fake-work")
    }

    func testWrapperIsCodesigned() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .badge(.red), outputDir: out)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", wrapper.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "wrapper should pass codesign --verify")
    }

    func testRegenerateInPlace() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: out)
        // Same slug, new display name — simulates the Edit flow.
        let renamed = InstanceSpec(name: "Fake Personal", slug: "fake-work", target: spec.target)
        let wrapper = try generator.generate(spec: renamed, icon: .badge(.green), outputDir: out)
        XCTAssertEqual(wrapper.lastPathComponent, "Fake Personal.app")
        // The old bundle name must be gone (regenerated, not duplicated).
        let contents = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertEqual(contents.sorted(), ["Fake Personal.app"])
    }

    func testCustomIconIsUsed() throws {
        let png = tmp.appendingPathComponent("custom.png")
        let img = NSImage(size: NSSize(width: 64, height: 64))
        img.lockFocus(); NSColor.purple.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); img.unlockFocus()
        let tiff = img.tiffRepresentation!
        try NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!.write(to: png)

        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .custom(png), outputDir: out)
        XCTAssertNotNil(NSImage(contentsOf: wrapper.appendingPathComponent("Contents/Resources/icon.icns")))
    }
}
