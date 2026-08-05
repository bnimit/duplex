import XCTest
@testable import DuplyKit

final class ScaffoldTests: XCTestCase {
    func testPlistKeys() {
        XCTAssertEqual(DuplyPlistKey.targetBundleID, "DuplyTargetBundleID")
        XCTAssertEqual(DuplyPlistKey.bundleIDPrefix, "com.duply.")
    }
}
