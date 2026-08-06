import XCTest
@testable import DuplexKit

final class InstanceFilterTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(InstanceFilter.matches(name: "Claude Work", targetPath: "/Applications/Claude.app", query: ""))
        XCTAssertTrue(InstanceFilter.matches(name: "Claude Work", targetPath: "/Applications/Claude.app", query: "   "))
    }
    func testMatchesInstanceNameCaseInsensitively() {
        XCTAssertTrue(InstanceFilter.matches(name: "Claude Work", targetPath: "/Applications/Claude.app", query: "work"))
        XCTAssertFalse(InstanceFilter.matches(name: "Claude Work", targetPath: "/Applications/Claude.app", query: "slack"))
    }
    func testMatchesTargetAppName() {
        XCTAssertTrue(InstanceFilter.matches(name: "Second Brain", targetPath: "/Applications/Claude.app", query: "claude"))
    }
    func testDiacriticInsensitive() {
        XCTAssertTrue(InstanceFilter.matches(name: "Émile", targetPath: "/Applications/X.app", query: "emile"))
    }
}
