import XCTest
@testable import DuplexKit

final class AppInspectorTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testDetectsElectronApp() throws {
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        XCTAssertTrue(AppInspector.isElectronBased(app))
    }

    func testRejectsNonElectronApp() throws {
        let app = try FixtureFactory.makeFakeApp(named: "Plain", bundleID: "com.x.plain", electron: false, in: tmp)
        XCTAssertFalse(AppInspector.isElectronBased(app))
        XCTAssertThrowsError(try AppInspector.inspect(app)) { error in
            XCTAssertEqual(error as? AppInspectorError, .notElectron("Plain"))
        }
    }

    func testInspectExtractsMetadata() throws {
        let app = try FixtureFactory.makeFakeApp(
            named: "Fake", bundleID: "com.x.fake", electron: true, schemes: ["fake", "msauth.fake"], in: tmp)
        let target = try AppInspector.inspect(app)
        XCTAssertEqual(target.bundleID, "com.x.fake")
        XCTAssertEqual(target.name, "Fake")
        XCTAssertEqual(target.executable, "Fake")
        XCTAssertEqual(target.urlSchemes, ["fake", "msauth.fake"])
        XCTAssertEqual(target.url, app)
    }

    func testInspectMissingPlistThrows() throws {
        let bogus = tmp.appendingPathComponent("Empty.app")
        try FileManager.default.createDirectory(at: bogus, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AppInspector.inspect(bogus)) { error in
            XCTAssertEqual(error as? AppInspectorError, .missingInfoPlist)
        }
    }
}
