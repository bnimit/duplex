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

    func testWrapperLaunchesTargetWithUserDataDir() throws {
        let fakeApp = try FixtureFactory.makeFakeApp(
            named: "FakeTron", bundleID: "com.duplex-tests.faketron", electron: true, in: tmp)
        let spec = InstanceSpec(name: "FakeTron Work", slug: "faketron-work",
                                target: try AppInspector.inspect(fakeApp))
        let gen = WrapperGenerator(launcherBinary: try builtLauncherURL())
        let wrapper = try gen.generate(spec: spec, icon: .badge(.green),
                                       outputDir: tmp.appendingPathComponent("wrappers"))

        let fakeHome = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher")
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = fakeHome.path
        p.environment = env
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)

        // The fake target writes its argv next to its bundle (see FixtureFactory).
        let argsFile = tmp.appendingPathComponent("args.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: argsFile.path), "fake target should have run")
        let args = try String(contentsOf: argsFile, encoding: .utf8)
        let expectedDataDir = fakeHome.path + "/Library/Application Support/Duplex/faketron-work/data"
        XCTAssertTrue(args.contains("--user-data-dir=\(expectedDataDir)"),
                      "target must receive --user-data-dir; got: \(args)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDataDir),
                      "launcher must create the data dir")
    }
}
