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

    private func change(_ recorded: String?, _ installed: String?) -> LauncherLogic.VersionChange {
        LauncherLogic.versionChange(recorded: recorded, installed: installed)
    }

    func testVersionChangeUnchanged() {
        XCTAssertEqual(change("1.0 (100)", "1.0 (100)"), .unchanged)
        XCTAssertEqual(change(nil, "1.0 (100)"), .unchanged, "legacy wrapper: nothing recorded")
        XCTAssertEqual(change("1.0 (100)", nil), .unchanged, "target plist unreadable: leave it")
        XCTAssertEqual(change(nil, nil), .unchanged)
        XCTAssertFalse(LauncherLogic.VersionChange.unchanged.rebuilds)
    }

    func testVersionChangeUpgrade() {
        XCTAssertEqual(change("1.0 (100)", "1.1 (101)"), .upgrade)
        XCTAssertEqual(change("1.0 (100)", "1.0 (101)"), .upgrade, "build alone moved forward")
        XCTAssertEqual(change("1.2.9 (1)", "1.10.0 (1)"), .upgrade, "numeric, not alphabetical")
        XCTAssertEqual(change("5.11492.5 (5.11492.5)", "5.11493.1 (5.11493.1)"), .upgrade)
        XCTAssertEqual(change("1.2 (1)", "1.2.1 (1)"), .upgrade, "a deeper component appeared")
        XCTAssertTrue(LauncherLogic.VersionChange.upgrade.rebuilds)
    }

    func testVersionChangeDowngrade() {
        XCTAssertEqual(change("1.1 (101)", "1.0 (100)"), .downgrade)
        XCTAssertEqual(change("1.0 (101)", "1.0 (100)"), .downgrade, "build alone went back")
        XCTAssertEqual(change("1.10.0 (1)", "1.2.9 (1)"), .downgrade, "numeric, not alphabetical")
        XCTAssertEqual(change("26.1029.61003 (26.1029.61003)", "26.1028.1 (26.1028.1)"), .downgrade)
        XCTAssertEqual(change("1.0.1 (101)", "1.0 (100)"), .downgrade)
        XCTAssertFalse(LauncherLogic.VersionChange.downgrade.rebuilds,
                       "a downgrade must never resync the clone backwards")
    }

    func testVersionChangeShortVersionOutranksBuild() {
        XCTAssertEqual(change("1.0 (999)", "1.1 (1)"), .upgrade,
                       "CFBundleShortVersionString decides; the build is only a tiebreaker")
        XCTAssertEqual(change("1.1 (1)", "1.0 (999)"), .downgrade)
    }

    func testVersionChangeUnparseableFallsBackToRebuilding() {
        XCTAssertEqual(change("1.0-beta (100)", "1.0 (100)"), .indeterminate, "recorded will not parse")
        XCTAssertEqual(change("1.0 (100)", "2026.11.21-nightly (100)"), .indeterminate, "installed will not parse")
        XCTAssertEqual(change("1.0 (abc)", "1.0 (abd)"), .indeterminate, "build will not parse")
        XCTAssertEqual(change("", "1.0 (100)"), .indeterminate, "empty recorded version")
        XCTAssertTrue(LauncherLogic.VersionChange.indeterminate.rebuilds,
                      "an unorderable difference keeps the old rebuild-on-any-difference behavior")
    }

    func testVersionChangeDifferingComponentCounts() {
        XCTAssertEqual(change("1.2 (1)", "1.2.0 (1)"), .indeterminate,
                       "numerically equal, textually different: rebuild rather than guess")
        XCTAssertEqual(change("1.2.0 (1)", "1.2 (1)"), .indeterminate)
        XCTAssertEqual(change("1.2 (1.0)", "1.2.0 (1)"), .indeterminate)
    }

    func testVersionChangeBuildOnlyStrings() {
        // InstancePlist.sourceVersion writes "(<build>)" when the app has no short version.
        XCTAssertEqual(change("(100)", "(101)"), .upgrade)
        XCTAssertEqual(change("(101)", "(100)"), .downgrade)
        XCTAssertEqual(change("(100)", "(100)"), .unchanged)
    }

    func testAppVersionParsing() {
        XCTAssertEqual(AppVersion("1.0 (100)")?.short, [1, 0])
        XCTAssertEqual(AppVersion("1.0 (100)")?.build, [100])
        XCTAssertEqual(AppVersion("5.11492.5")?.short, [5, 11492, 5])
        XCTAssertEqual(AppVersion("5.11492.5")?.build, [])
        XCTAssertEqual(AppVersion("(155)")?.short, [])
        XCTAssertEqual(AppVersion("(155)")?.build, [155])
        XCTAssertNil(AppVersion(""), "nothing to order")
        XCTAssertNil(AppVersion("1.0.x"))
        XCTAssertNil(AppVersion("1..0"))
        XCTAssertNil(AppVersion("v1.0"))
    }

    func testCodexGetsPrivateCodexHome() {
        let dataDir = LauncherLogic.dataDir(slug: "codex-work", homePath: "/Users/u")
        let expected = ["CODEX_HOME": "/Users/u/Library/Application Support/Duplex/codex-work/codex-home"]
        let app = URL(fileURLWithPath: "/Applications/Codex.app")
        XCTAssertEqual(LauncherLogic.extraEnvironment(
            targetBundleID: "com.openai.codex", targetURL: app, dataDir: dataDir, fileExists: { _ in false }),
            expected)
        XCTAssertEqual(LauncherLogic.extraEnvironment(
            targetBundleID: "com.openai.renamed", targetURL: app, dataDir: dataDir,
            fileExists: { $0 == "/Applications/Codex.app/Contents/Resources/codex-cli" }),
            expected, "recognized by the codex-cli it ships even if the ID changes")
        XCTAssertEqual(LauncherLogic.extraEnvironment(
            targetBundleID: "com.anthropic.claudefordesktop", targetURL: URL(fileURLWithPath: "/Applications/Claude.app"),
            dataDir: dataDir, fileExists: { _ in false }),
            [:])
    }
}
