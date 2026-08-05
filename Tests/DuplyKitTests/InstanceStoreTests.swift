import XCTest
@testable import DuplyKit

final class InstanceStoreTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func generateWrapper(named name: String, slug: String) throws {
        let app = try FixtureFactory.makeFakeApp(
            named: "Fake", bundleID: "com.x.fake", electron: true, schemes: ["fake"], in: tmp)
        let spec = InstanceSpec(name: name, slug: slug, target: try AppInspector.inspect(app))
        let gen = WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls"))
        _ = try gen.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
    }

    func testScanFindsOnlyDuplyWrappers() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        // A non-Duply .app in the same folder must be ignored.
        _ = try FixtureFactory.makeFakeApp(
            named: "Bystander", bundleID: "com.x.by", electron: false,
            in: tmp.appendingPathComponent("wrappers"))

        let instances = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: "/tmp/h")
        XCTAssertEqual(instances.count, 1)
        let inst = instances[0]
        XCTAssertEqual(inst.name, "Fake Work")
        XCTAssertEqual(inst.slug, "fake-work")
        XCTAssertEqual(inst.targetBundleID, "com.x.fake")
        XCTAssertEqual(inst.urlSchemes, ["fake"])
        XCTAssertEqual(inst.dataDir.path, "/tmp/h/Library/Application Support/Duply/fake-work/data")
    }

    func testDataSize() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        var inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        XCTAssertEqual(InstanceStore.dataSize(of: inst), 0) // no data dir yet
        try FileManager.default.createDirectory(at: inst.dataDir, withIntermediateDirectories: true)
        try Data(count: 2048).write(to: inst.dataDir.appendingPathComponent("blob"))
        inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        XCTAssertGreaterThanOrEqual(InstanceStore.dataSize(of: inst), 2048)
    }

    func testDeleteWrapperOnly() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        try FileManager.default.createDirectory(at: inst.dataDir, withIntermediateDirectories: true)
        try InstanceStore.delete(inst, includingData: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inst.wrapperURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inst.dataDir.path))
    }

    func testDeleteIncludingData() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        try FileManager.default.createDirectory(at: inst.dataDir, withIntermediateDirectories: true)
        try InstanceStore.delete(inst, includingData: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inst.wrapperURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inst.dataDir.path))
    }

    func testScanIgnoresHiddenStagingBundles() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        let out = tmp.appendingPathComponent("wrappers")
        // Simulate a crashed generate: hidden staging bundle with a valid Duply plist.
        let staleContents = out.appendingPathComponent(".duply-staging-ghost.app/Contents")
        try FileManager.default.createDirectory(at: staleContents, withIntermediateDirectories: true)
        let app = try FixtureFactory.makeFakeApp(named: "Ghost", bundleID: "com.x.ghost", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Ghost", slug: "ghost", target: try AppInspector.inspect(app))
        let data = try PropertyListSerialization.data(fromPropertyList: WrapperPlist.plist(for: spec), format: .xml, options: 0)
        try data.write(to: staleContents.appendingPathComponent("Info.plist"))

        let instances = InstanceStore.scan(outputDir: out, homePath: "/tmp/h")
        XCTAssertEqual(instances.map(\.slug), ["fake-work"])
    }
}
