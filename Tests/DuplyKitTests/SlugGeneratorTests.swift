import XCTest
@testable import DuplyKit

final class SlugGeneratorTests: XCTestCase {
    func testBasicSlugging() {
        XCTAssertEqual(SlugGenerator.slug(from: "Claude Work", existing: []), "claude-work")
        XCTAssertEqual(SlugGenerator.slug(from: "  A  B!! C_ ", existing: []), "a-b-c")
        XCTAssertEqual(SlugGenerator.slug(from: "Émile's Süper App", existing: []), "emile-s-super-app")
    }

    func testEmptyNameFallsBack() {
        XCTAssertEqual(SlugGenerator.slug(from: "!!!", existing: []), "instance")
    }

    func testUniquenessSuffix() {
        XCTAssertEqual(SlugGenerator.slug(from: "Claude Work", existing: ["claude-work"]), "claude-work-2")
        XCTAssertEqual(SlugGenerator.slug(from: "Claude Work", existing: ["claude-work", "claude-work-2"]), "claude-work-3")
    }
}
