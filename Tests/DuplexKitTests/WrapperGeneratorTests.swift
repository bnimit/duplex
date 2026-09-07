import XCTest
import AppKit
@testable import DuplexKit

final class WrapperGeneratorTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeSpec(helper: Bool = false, nativeExecutable: Bool = false,
                          provisionProfile: Bool = false, iconName: String? = nil,
                          documentTypes: Bool = false, shipsIconIcns: Bool = false) throws -> InstanceSpec {
        let app = try FixtureFactory.makeFakeApp(
            named: "Fake", bundleID: "com.x.fake", electron: true, schemes: ["fake"],
            helper: helper, nativeExecutable: nativeExecutable, provisionProfile: provisionProfile,
            iconName: iconName, documentTypes: documentTypes, shipsIconIcns: shipsIconIcns, in: tmp)
        return InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
    }

    private func plist(of bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    // /bin/ls is a real Mach-O so codesign of the wrapper succeeds in tests.
    private var generator: WrapperGenerator { WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls")) }

    func testGeneratesCompleteBundle() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .badge(.blue), outputDir: out)

        XCTAssertEqual(wrapper.lastPathComponent, "Fake Work.app")
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/PkgInfo").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Resources/icon.icns").path))
        XCTAssertTrue(fm.isExecutableFile(atPath: wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher").path))
        // The clone carries the target's own binary and frameworks.
        XCTAssertTrue(fm.isExecutableFile(atPath: wrapper.appendingPathComponent("Contents/MacOS/Fake").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path))

        let plist = try plist(of: wrapper)
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.duplex.fake-work")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Fake Work")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Fake", "kept from the target")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "duplex-launcher")
        XCTAssertEqual(plist[DuplexPlistKey.instanceSlug] as? String, "fake-work")
        XCTAssertEqual(plist[DuplexPlistKey.targetExecutable] as? String, "Fake")
        XCTAssertEqual(plist[DuplexPlistKey.formatVersion] as? Int, 2)
        XCTAssertEqual(plist[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)")
    }

    func testTargetIsUntouched() throws {
        let spec = try makeSpec(provisionProfile: true)
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let target = try plist(of: spec.target.url)
        XCTAssertEqual(target["CFBundleIdentifier"] as? String, "com.x.fake")
        XCTAssertNil(target[DuplexPlistKey.instanceSlug])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: spec.target.url.appendingPathComponent("Contents/embedded.provisionprofile").path))
    }

    func testRemovesProvisionProfileAndQuarantine() throws {
        let spec = try makeSpec(provisionProfile: true)
        let value = "0083;00000000;Safari;"
        XCTAssertEqual(setxattr(spec.target.url.path, "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)
        XCTAssertEqual(setxattr(spec.target.url.appendingPathComponent("Contents/MacOS/Fake").path,
                                "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)

        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: wrapper.appendingPathComponent("Contents/embedded.provisionprofile").path))
        XCTAssertEqual(getxattr(wrapper.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
        XCTAssertEqual(getxattr(wrapper.appendingPathComponent("Contents/MacOS/Fake").path,
                                "com.apple.quarantine", nil, 0, 0, 0), -1)
    }

    func testHelpersAndMachOExecutablesAreAdhocSigned() throws {
        let spec = try makeSpec(helper: true, nativeExecutable: true)
        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/Frameworks/Fake Helper.app")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/Fake-native")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper), "adhoc")
        // The script main executable cannot carry an embedded Mach-O signature, but codesign
        // ad-hoc-signs it anyway in a generic format: a loose, unsigned file directly in MacOS
        // would otherwise fail bundle-level codesign validation.
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/Fake")), "adhoc")
    }

    func testDropsIconNameAndDocumentTypesKeepsURLTypes() throws {
        let spec = try makeSpec(iconName: "Fake", documentTypes: true)
        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let plist = try plist(of: wrapper)
        XCTAssertNil(plist["CFBundleIconName"])
        XCTAssertNil(plist["CFBundleDocumentTypes"])
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "icon.icns")
        let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        XCTAssertEqual(urlTypes?.first?["CFBundleURLSchemes"] as? [String], ["fake"])
    }

    func testWrapperIsCodesigned() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(helper: true), icon: .badge(.red), outputDir: out)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", "--strict", wrapper.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "clone should pass codesign --verify --strict")
    }

    func testRegenerateInPlace() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: out)
        // Same slug, new display name: simulates the Edit flow.
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

    func testRefusesToOverwriteBystanderApp() throws {
        let out = tmp.appendingPathComponent("wrappers")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = try FixtureFactory.makeFakeApp(named: "Fake Work", bundleID: "com.other.real", electron: false, in: out)
        XCTAssertThrowsError(try generator.generate(spec: try makeSpec(), icon: .badge(.blue), outputDir: out)) { error in
            guard case WrapperGeneratorError.destinationOccupied = error else { return XCTFail("wrong error: \(error)") }
        }
        let data = try Data(contentsOf: out.appendingPathComponent("Fake Work.app/Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.other.real")
    }

    func testRefusesNameCollisionWithDifferentSlugWrapper() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: out)
        let colliding = InstanceSpec(name: "Fake Work", slug: "fake-work-2", target: spec.target)
        XCTAssertThrowsError(try generator.generate(spec: colliding, icon: .badge(.red), outputDir: out)) { error in
            guard case WrapperGeneratorError.destinationOccupied = error else { return XCTFail("wrong error: \(error)") }
        }
        let data = try Data(contentsOf: out.appendingPathComponent("Fake Work.app/Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(plist[DuplexPlistKey.instanceSlug] as? String, "fake-work")
    }

    func testFailedBuildKeepsOldWrapper() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: out)
        let broken = WrapperGenerator(launcherBinary: tmp.appendingPathComponent("no-such-launcher"))
        XCTAssertThrowsError(try broken.generate(spec: spec, icon: .badge(.green), outputDir: out))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: out.appendingPathComponent("Fake Work.app/Contents/MacOS/duplex-launcher").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasPrefix(".duplex-staging") }
        XCTAssertEqual(leftovers, [])
    }

    func testKeepExistingIconPreservesIconBytes() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        let wrapper = try generator.generate(spec: spec, icon: .badge(.red), outputDir: out)
        let originalIconData = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Resources/icon.icns"))

        let regenerated = try generator.generate(spec: spec, icon: .keepExisting, outputDir: out)
        let regeneratedIconData = try Data(contentsOf: regenerated.appendingPathComponent("Contents/Resources/icon.icns"))

        XCTAssertEqual(originalIconData, regeneratedIconData)
    }

    func testKeepExistingIconWithNoOldWrapperFallsBack() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .keepExisting, outputDir: out)
        let iconURL = wrapper.appendingPathComponent("Contents/Resources/icon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertNotNil(NSImage(contentsOf: iconURL))
    }

    func testOriginalIconCopiesTargetIcnsExactly() throws {
        let spec = try makeSpec()

        // Write a real .icns into the target app's Resources and point CFBundleIconFile at it.
        let iconImage = NSImage(size: NSSize(width: 64, height: 64))
        iconImage.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); iconImage.unlockFocus()

        let resources = spec.target.url.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let icnsURL = resources.appendingPathComponent("AppIcon.icns")
        try IconBadger.writeICNS(iconImage, to: icnsURL)

        let plistURL = spec.target.url.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["CFBundleIconFile"] = "AppIcon"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)

        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: spec, icon: .original, outputDir: out)

        let targetIcnsData = try Data(contentsOf: icnsURL)
        let wrapperIcnsData = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Resources/icon.icns"))
        XCTAssertEqual(targetIcnsData, wrapperIcnsData, "the wrapper's icon should be a byte-identical copy of the target's")
    }

    func testOriginalIconFallsBackWhenTargetHasNoIcns() throws {
        let out = tmp.appendingPathComponent("wrappers")
        // makeSpec()'s fake app has no CFBundleIconFile / .icns at all.
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .original, outputDir: out)
        let iconURL = wrapper.appendingPathComponent("Contents/Resources/icon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertNotNil(NSImage(contentsOf: iconURL))
    }

    func testOriginalIconOverwritesTargetIconFile() throws {
        let spec = try makeSpec(shipsIconIcns: true)
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: spec, icon: .original, outputDir: out)

        let targetIcnsData = try Data(contentsOf: spec.target.url.appendingPathComponent("Contents/Resources/icon.icns"))
        let wrapperIcnsData = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Resources/icon.icns"))
        XCTAssertEqual(targetIcnsData, wrapperIcnsData)
    }

    func testKeepExistingIconOverExistingWrapperWhenTargetShipsIconFile() throws {
        let spec = try makeSpec(shipsIconIcns: true)
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: spec, icon: .badge(.red), outputDir: out)
        let firstIconData = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Resources/icon.icns"))

        let regenerated = try generator.generate(spec: spec, icon: .keepExisting, outputDir: out)
        let regeneratedIconData = try Data(contentsOf: regenerated.appendingPathComponent("Contents/Resources/icon.icns"))

        XCTAssertEqual(firstIconData, regeneratedIconData)
    }

    func testWrittenIcnsContainsHiResRep() throws {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(); image.unlockFocus()

        let out = tmp.appendingPathComponent("hires.icns")
        try IconBadger.writeICNS(image, to: out)

        guard let loaded = NSImage(contentsOf: out) else { return XCTFail("could not load written icns") }
        let hasHiRes = loaded.representations.contains { $0.pixelsWide >= 1024 }
        XCTAssertTrue(hasHiRes, "written .icns should contain a >=1024px representation")
    }

    func testStaleStagingLeftoverDoesNotBreakGenerate() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let spec = try makeSpec()
        // Simulate a crashed prior run: a stale staging bundle with this slug's plist.
        let staleContents = out.appendingPathComponent(".duplex-staging-fake-work.app/Contents")
        try FileManager.default.createDirectory(at: staleContents, withIntermediateDirectories: true)
        let plist = FixtureFactory.legacyDuplexPlist(spec: spec)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: staleContents.appendingPathComponent("Info.plist"))

        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: out)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasPrefix(".duplex-staging") }
        XCTAssertEqual(leftovers, [])
    }
}
