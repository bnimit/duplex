import XCTest
@testable import DuplexKit

final class InstanceRuntimeTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testFreshInstanceIsNotRunning() throws {
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
        _ = try WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls"))
            .generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        XCTAssertFalse(InstanceRuntime.isRunning(inst))
        XCTAssertEqual(InstanceRuntime.runningApplications(for: inst), [])
    }

    func testQuitOfNothingSucceedsImmediately() async throws {
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
        _ = try WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls"))
            .generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        let quit = await InstanceRuntime.quit(inst, timeout: 1)
        XCTAssertTrue(quit)
    }
}
