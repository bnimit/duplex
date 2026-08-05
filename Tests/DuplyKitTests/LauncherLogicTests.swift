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

    func testResolveTargetLSResolved() {
        // LS-resolved and exists → LS URL wins even when fallback also exists
        let lsResolved = URL(fileURLWithPath: "/Applications/Fake.app")
        let fallbackPath = "/alt/Fake.app"
        let existing = Set(["/Applications/Fake.app", "/alt/Fake.app"])
        let result = LauncherLogic.resolveTarget(
            lsResolved: lsResolved,
            fallbackPath: fallbackPath,
            fileExists: { existing.contains($0) })
        XCTAssertEqual(result, lsResolved)
    }

    func testResolveTargetLSResolvedButStale() {
        // LS-resolved but stale (doesn't exist) → fallback used
        let lsResolved = URL(fileURLWithPath: "/Applications/Fake.app")
        let fallbackPath = "/alt/Fake.app"
        let existing = Set(["/alt/Fake.app"])
        let result = LauncherLogic.resolveTarget(
            lsResolved: lsResolved,
            fallbackPath: fallbackPath,
            fileExists: { existing.contains($0) })
        XCTAssertEqual(result, URL(fileURLWithPath: fallbackPath))
    }

    func testResolveTargetLSNil() {
        // LS nil → fallback used
        let fallbackPath = "/alt/Fake.app"
        let existing = Set(["/alt/Fake.app"])
        let result = LauncherLogic.resolveTarget(
            lsResolved: nil,
            fallbackPath: fallbackPath,
            fileExists: { existing.contains($0) })
        XCTAssertEqual(result, URL(fileURLWithPath: fallbackPath))
    }

    func testResolveTargetNeitherExists() {
        // Neither exists → nil
        let lsResolved = URL(fileURLWithPath: "/Applications/Fake.app")
        let fallbackPath = "/alt/Fake.app"
        let existing = Set<String>([])
        let result = LauncherLogic.resolveTarget(
            lsResolved: lsResolved,
            fallbackPath: fallbackPath,
            fileExists: { existing.contains($0) })
        XCTAssertNil(result)
    }
}
