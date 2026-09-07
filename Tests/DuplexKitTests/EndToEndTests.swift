import XCTest
@testable import DuplexKit

/// Full-loop test: generate a wrapper with the REAL duplex-launcher binary around a fake
/// Electron app whose executable dumps its argv, run the wrapper's launcher with a
/// redirected HOME, and assert the target ran with --user-data-dir and the data dir exists.
final class EndToEndTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// The test bundle lives in .build/<config>/; the launcher product sits alongside it.
    private func builtLauncherURL() throws -> URL {
        let buildDir = Bundle(for: EndToEndTests.self).bundleURL.deletingLastPathComponent()
        let launcher = buildDir.appendingPathComponent("duplex-launcher")
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: launcher.path),
            "duplex-launcher not built; run `swift build` first")
        return launcher
    }

    private func runLauncher(in wrapper: URL, home: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher")
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        p.environment = env
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func plist(of bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    /// The fixture script writes "$0 $@" next to the bundle it ran from: for a clone, that is
    /// the wrappers directory.
    private func recordedArgs() throws -> String {
        let argsFile = tmp.appendingPathComponent("wrappers/args.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: argsFile.path), "the clone's binary should have run")
        return try String(contentsOf: argsFile, encoding: .utf8)
    }

    private func makeWrapper() throws -> (app: URL, wrapper: URL) {
        let fakeApp = try FixtureFactory.makeFakeApp(
            named: "FakeTron", bundleID: "com.duplex-tests.faketron", electron: true, in: tmp)
        let spec = InstanceSpec(name: "FakeTron Work", slug: "faketron-work",
                                target: try AppInspector.inspect(fakeApp))
        let gen = WrapperGenerator(launcherBinary: try builtLauncherURL())
        let wrapper = try gen.generate(spec: spec, icon: .badge(.green),
                                       outputDir: tmp.appendingPathComponent("wrappers"))
        return (fakeApp, wrapper)
    }

    func testLauncherRunsTheClonesOwnBinaryWithUserDataDir() throws {
        let (_, wrapper) = try makeWrapper()
        let fakeHome = tmp.appendingPathComponent("home")
        XCTAssertEqual(try runLauncher(in: wrapper, home: fakeHome), 0)

        let args = try recordedArgs()
        XCTAssertTrue(args.hasPrefix(wrapper.appendingPathComponent("Contents/MacOS/FakeTron").path),
                      "must run the binary inside the clone, not the original; got: \(args)")
        let expectedDataDir = fakeHome.path + "/Library/Application Support/Duplex/faketron-work/data"
        XCTAssertTrue(args.contains("--user-data-dir=\(expectedDataDir)"), "got: \(args)")
        XCTAssertTrue(args.contains("--use-mock-keychain"), "got: \(args)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDataDir), "launcher must create the data dir")
    }

    func testLauncherRegeneratesCloneWhenTargetVersionChanges() throws {
        let (fakeApp, wrapper) = try makeWrapper()
        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)")

        try FixtureFactory.setVersion(of: fakeApp, short: "2.0", build: "200")
        XCTAssertEqual(try runLauncher(in: wrapper, home: tmp.appendingPathComponent("home")), 0)

        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "2.0 (200)",
                       "clone should have been rebuilt from the updated original")
        XCTAssertEqual(try plist(of: wrapper)["CFBundleShortVersionString"] as? String, "2.0")
        XCTAssertTrue(try recordedArgs().contains("--user-data-dir="))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tmp.appendingPathComponent("wrappers").path)
            .filter { $0.hasPrefix(".duplex-staging") }
        XCTAssertEqual(leftovers, [])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tmp.appendingPathComponent("home/Library/Application Support/Duplex/faketron-work/resync.lock").path),
            "lock file is created under the instance's App Support folder")
    }

    func testLauncherRunsExistingCloneWhenRegenerationFails() throws {
        let (fakeApp, wrapper) = try makeWrapper()
        try FixtureFactory.setVersion(of: fakeApp, short: "2.0", build: "200")
        // Without the framework the original no longer passes AppInspector, so regeneration
        // fails; the launcher must still run the stale clone.
        try FileManager.default.removeItem(at: fakeApp.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"))

        XCTAssertEqual(try runLauncher(in: wrapper, home: tmp.appendingPathComponent("home")), 0)
        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)", "unchanged")
        XCTAssertTrue(try recordedArgs().contains("--use-mock-keychain"))
    }

    func testLauncherRebuildsCloneWhoseBinaryIsMissing() throws {
        let (_, wrapper) = try makeWrapper()
        let cloneBinary = wrapper.appendingPathComponent("Contents/MacOS/FakeTron")
        try FileManager.default.removeItem(at: cloneBinary)

        XCTAssertEqual(try runLauncher(in: wrapper, home: tmp.appendingPathComponent("home")), 0)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: cloneBinary.path), "clone should have been rebuilt")
        XCTAssertTrue(try recordedArgs().hasPrefix(cloneBinary.path), "the rebuilt clone's binary should have run")
    }
}
