import XCTest
@testable import DuplexKit

final class BundleClonerTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    private func makeTree() throws -> URL {
        let src = tmp.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "one".write(to: src.appendingPathComponent("sub/a.txt"), atomically: true, encoding: .utf8)
        return src
    }

    func testCloneProducesIndependentCopy() throws {
        let src = try makeTree()
        let dst = tmp.appendingPathComponent("dst")
        try BundleCloner.clone(src, to: dst)
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("sub/a.txt"), encoding: .utf8), "one")
        try "two".write(to: dst.appendingPathComponent("sub/a.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: src.appendingPathComponent("sub/a.txt"), encoding: .utf8), "one",
                       "writing to the clone must not touch the source")
    }

    func testCloneRefusesExistingDestination() throws {
        let src = try makeTree()
        let dst = tmp.appendingPathComponent("dst")
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BundleCloner.clone(src, to: dst))
    }

    func testStripQuarantineRemovesAttributeEverywhere() throws {
        let src = try makeTree()
        let file = src.appendingPathComponent("sub/a.txt")
        let value = "0083;00000000;Safari;"
        for path in [src.path, file.path] {
            XCTAssertEqual(setxattr(path, "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)
        }
        BundleCloner.stripQuarantine(at: src)
        for path in [src.path, file.path] {
            XCTAssertEqual(getxattr(path, "com.apple.quarantine", nil, 0, 0, 0), -1, "\(path) still quarantined")
        }
    }

    func testIsMachO() throws {
        XCTAssertTrue(BundleCloner.isMachO(URL(fileURLWithPath: "/bin/ls")))
        let script = tmp.appendingPathComponent("s.sh")
        try "#!/bin/bash\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertFalse(BundleCloner.isMachO(script))
        let empty = tmp.appendingPathComponent("empty")
        try Data().write(to: empty)
        XCTAssertFalse(BundleCloner.isMachO(empty))
        XCTAssertFalse(BundleCloner.isMachO(tmp.appendingPathComponent("missing")))
    }

    func testMachOExecutablesListsOnlyMachOFiles() throws {
        let dir = tmp.appendingPathComponent("MacOS")
        try fm.createDirectory(at: dir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: dir.appendingPathComponent("native"))
        try "#!/bin/bash\n".write(to: dir.appendingPathComponent("script"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BundleCloner.machOExecutables(in: dir).map(\.lastPathComponent), ["native"])
        XCTAssertEqual(BundleCloner.machOExecutables(in: tmp.appendingPathComponent("nope")), [])
    }
}
