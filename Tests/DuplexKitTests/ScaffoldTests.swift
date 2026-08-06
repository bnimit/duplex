import XCTest
@testable import DuplexKit

final class ScaffoldTests: XCTestCase {
    func testPlistKeys() {
        XCTAssertEqual(DuplexPlistKey.targetBundleID, "DuplexTargetBundleID")
        XCTAssertEqual(DuplexPlistKey.bundleIDPrefix, "com.duplex.")
    }
}
