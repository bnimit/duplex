import XCTest
@testable import DuplexKit

final class InstancePlistTests: XCTestCase {
    private let target = TargetApp(
        url: URL(fileURLWithPath: "/Applications/Fake.app"),
        bundleID: "com.x.fake", name: "Fake", executable: "Fake", urlSchemes: ["fake"])
    private var spec: InstanceSpec { InstanceSpec(name: "Fake Work", slug: "fake-work", target: target) }

    private var original: [String: Any] {
        [
            "CFBundleIdentifier": "com.x.fake",
            "CFBundleName": "Fake",
            "CFBundleDisplayName": "Fake",
            "CFBundleExecutable": "Fake",
            "CFBundleIconFile": "electron.icns",
            "CFBundleIconName": "Fake",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
            "CFBundleDocumentTypes": [["CFBundleTypeName": "Thing"]],
            "UTExportedTypeDeclarations": [["UTTypeIdentifier": "com.x.thing"]],
            "CFBundleURLTypes": [["CFBundleURLName": "Fake", "CFBundleURLSchemes": ["fake"]]],
            "ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "abc"]],
            "LSMinimumSystemVersion": "12.0",
        ]
    }

    func testPatchesIdentityKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p["CFBundleIdentifier"] as? String, "com.duplex.fake-work")
        XCTAssertEqual(p["CFBundleDisplayName"] as? String, "Fake Work")
        XCTAssertEqual(p["CFBundleExecutable"] as? String, "duplex-launcher")
        XCTAssertEqual(p["CFBundleIconFile"] as? String, "icon.icns")
    }

    func testKeepsElectronCriticalKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p["CFBundleName"] as? String, "Fake", "Electron derives helper app names from CFBundleName")
        XCTAssertNotNil(p["ElectronAsarIntegrity"])
        XCTAssertEqual(p["LSMinimumSystemVersion"] as? String, "12.0")
        XCTAssertEqual(p["CFBundleShortVersionString"] as? String, "1.2.3")
        let urlTypes = p["CFBundleURLTypes"] as? [[String: Any]]
        XCTAssertEqual(urlTypes?.first?["CFBundleURLSchemes"] as? [String], ["fake"])
    }

    func testRemovesKeysThatWouldLeakOrClutter() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertNil(p["CFBundleIconName"], "an Assets.car icon name would override icon.icns")
        XCTAssertNil(p["CFBundleDocumentTypes"])
        XCTAssertNil(p["UTExportedTypeDeclarations"])
    }

    func testAddsDuplexKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p[DuplexPlistKey.targetBundleID] as? String, "com.x.fake")
        XCTAssertEqual(p[DuplexPlistKey.targetPath] as? String, "/Applications/Fake.app")
        XCTAssertEqual(p[DuplexPlistKey.targetExecutable] as? String, "Fake")
        XCTAssertEqual(p[DuplexPlistKey.instanceSlug] as? String, "fake-work")
        XCTAssertEqual(p[DuplexPlistKey.instanceName] as? String, "Fake Work")
        XCTAssertEqual(p[DuplexPlistKey.formatVersion] as? Int, 2)
        XCTAssertEqual(p[DuplexPlistKey.sourceVersion] as? String, "1.2.3 (456)")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: p, format: .xml, options: 0))
    }

    func testSourceVersionCombinations() {
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"]), "1.0 (7)")
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleShortVersionString": "1.0"]), "1.0")
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleVersion": "7"]), "(7)")
        XCTAssertNil(InstancePlist.sourceVersion(of: [:]))
    }

    func testSourceVersionOfBundleOnDisk() throws {
        let tmp = try FixtureFactory.tempDir(name)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        XCTAssertEqual(InstancePlist.sourceVersion(ofBundleAt: app), "1.0 (100)")
        XCTAssertNil(InstancePlist.sourceVersion(ofBundleAt: tmp.appendingPathComponent("Nope.app")))
    }
}
