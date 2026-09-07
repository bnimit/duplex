import XCTest
@testable import DuplexKit

final class LauncherLogicTests: XCTestCase {
    func testConfigParsing() {
        let info: [String: Any] = [
            DuplexPlistKey.targetBundleID: "com.x.fake",
            DuplexPlistKey.targetPath: "/Applications/Fake.app",
            DuplexPlistKey.targetExecutable: "Fake",
            DuplexPlistKey.instanceSlug: "fake-work",
            DuplexPlistKey.instanceName: "Fake Work",
            DuplexPlistKey.sourceVersion: "1.0 (100)",
        ]
        XCTAssertEqual(
            LauncherLogic.config(from: info),
            LauncherConfig(targetBundleID: "com.x.fake", targetPath: "/Applications/Fake.app",
                           targetExecutable: "Fake", slug: "fake-work", name: "Fake Work",
                           sourceVersion: "1.0 (100)"))
    }

    func testConfigParsingLegacyWrapperHasNoCloneKeys() {
        let info: [String: Any] = [
            DuplexPlistKey.targetBundleID: "com.x.fake",
            DuplexPlistKey.targetPath: "/Applications/Fake.app",
            DuplexPlistKey.instanceSlug: "fake-work",
        ]
        let config = LauncherLogic.config(from: info)
        XCTAssertEqual(config?.slug, "fake-work")
        XCTAssertEqual(config?.name, "fake-work", "name falls back to the slug")
        XCTAssertNil(config?.targetExecutable)
        XCTAssertNil(config?.sourceVersion)
    }

    func testConfigParsingFailsWhenKeyMissing() {
        XCTAssertNil(LauncherLogic.config(from: [DuplexPlistKey.targetBundleID: "com.x.fake"]))
    }

    func testDataDir() {
        let dir = LauncherLogic.dataDir(slug: "fake-work", homePath: "/tmp/h")
        XCTAssertEqual(dir.path, "/tmp/h/Library/Application Support/Duplex/fake-work/data")
    }

    func testExecArguments() {
        let args = LauncherLogic.execArguments(
            targetExecutable: "/Applications/Fake Work.app/Contents/MacOS/Fake",
            dataDir: URL(fileURLWithPath: "/tmp/h/data"))
        XCTAssertEqual(args, ["/Applications/Fake Work.app/Contents/MacOS/Fake",
                              "--user-data-dir=/tmp/h/data",
                              "--use-mock-keychain"])
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

    func testNeedsResync() {
        XCTAssertTrue(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: "1.1 (101)"))
        XCTAssertFalse(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: "1.0 (100)"))
        XCTAssertFalse(LauncherLogic.needsResync(recorded: nil, installed: "1.0 (100)"), "legacy wrapper: nothing recorded")
        XCTAssertFalse(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: nil), "target plist unreadable: leave it")
        XCTAssertFalse(LauncherLogic.needsResync(recorded: nil, installed: nil))
    }
}
