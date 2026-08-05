import XCTest
@testable import DuplyKit

final class WrapperPlistTests: XCTestCase {
    func testPlistContents() throws {
        let target = TargetApp(
            url: URL(fileURLWithPath: "/Applications/Fake.app"),
            bundleID: "com.x.fake", name: "Fake", executable: "Fake",
            urlSchemes: ["fake"])
        let spec = InstanceSpec(name: "Fake Work", slug: "fake-work", target: target)
        let plist = WrapperPlist.plist(for: spec)

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.duply.fake-work")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Fake Work")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Fake Work")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "duply-launcher")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "icon")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "12.0")
        XCTAssertEqual(plist[DuplyPlistKey.targetBundleID] as? String, "com.x.fake")
        XCTAssertEqual(plist[DuplyPlistKey.targetPath] as? String, "/Applications/Fake.app")
        XCTAssertEqual(plist[DuplyPlistKey.instanceSlug] as? String, "fake-work")
        XCTAssertEqual(plist[DuplyPlistKey.instanceName] as? String, "Fake Work")

        let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        XCTAssertEqual(urlTypes?.count, 1)
        XCTAssertEqual(urlTypes?.first?["CFBundleURLSchemes"] as? [String], ["fake"])

        // Must serialize cleanly
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
    }

    func testNoSchemesOmitsURLTypes() {
        let target = TargetApp(
            url: URL(fileURLWithPath: "/Applications/Fake.app"),
            bundleID: "com.x.fake", name: "Fake", executable: "Fake", urlSchemes: [])
        let spec = InstanceSpec(name: "F", slug: "f", target: target)
        XCTAssertNil(WrapperPlist.plist(for: spec)["CFBundleURLTypes"])
    }
}
