import XCTest
@testable import DuplyKit

final class LauncherLogicTests: XCTestCase {
    func testConfigParsing() {
        let info: [String: Any] = [
            DuplyPlistKey.targetBundleID: "com.x.fake",
            DuplyPlistKey.targetPath: "/Applications/Fake.app",
            DuplyPlistKey.instanceSlug: "fake-work",
        ]
        XCTAssertEqual(
            LauncherLogic.config(from: info),
            LauncherConfig(targetBundleID: "com.x.fake", targetPath: "/Applications/Fake.app", slug: "fake-work"))
    }

    func testConfigParsingFailsWhenKeyMissing() {
        XCTAssertNil(LauncherLogic.config(from: [DuplyPlistKey.targetBundleID: "com.x.fake"]))
    }

    func testDataDir() {
        let dir = LauncherLogic.dataDir(slug: "fake-work", homePath: "/tmp/h")
        XCTAssertEqual(dir.path, "/tmp/h/Library/Application Support/Duply/fake-work/data")
    }

    func testExecArguments() {
        let args = LauncherLogic.execArguments(
            targetExecutable: "/Applications/Fake.app/Contents/MacOS/Fake",
            dataDir: URL(fileURLWithPath: "/tmp/h/data"))
        XCTAssertEqual(args, ["/Applications/Fake.app/Contents/MacOS/Fake", "--user-data-dir=/tmp/h/data"])
    }
}
