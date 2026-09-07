import XCTest
@testable import DuplexKit

final class SemanticVersionTests: XCTestCase {
    func testNewerVersionsAreDetected() {
        XCTAssertTrue(SemanticVersion.isNewer("1.2.1", than: "1.2.0"))
        XCTAssertTrue(SemanticVersion.isNewer("1.3.0", than: "1.2.9"))
        XCTAssertTrue(SemanticVersion.isNewer("2.0.0", than: "1.9.9"))
    }

    func testSameOrOlderVersionsAreNot() {
        XCTAssertFalse(SemanticVersion.isNewer("1.2.0", than: "1.2.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.2.0", than: "1.3.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.0", than: "1.0.1"))
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertTrue(SemanticVersion.isNewer("1.10.0", than: "1.9.0"), "10 is newer than 9")
        XCTAssertFalse(SemanticVersion.isNewer("1.9.0", than: "1.10.0"))
    }

    func testStripsTagPrefix() {
        XCTAssertTrue(SemanticVersion.isNewer("v1.3.0", than: "1.2.0"))
        XCTAssertFalse(SemanticVersion.isNewer("v1.2.0", than: "1.2.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(SemanticVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(SemanticVersion.isNewer("1.2.1", than: "1.2"))
        XCTAssertTrue(SemanticVersion.isNewer("1.3", than: "1.2.9"))
    }

    func testUnparseableInputNeverClaimsAnUpdate() {
        XCTAssertFalse(SemanticVersion.isNewer("banana", than: "1.2.0"))
        XCTAssertFalse(SemanticVersion.isNewer("", than: "1.2.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.2.1", than: "banana"))
    }
}

final class GitHubReleaseFeedTests: XCTestCase {
    func testParsesTagAndPageURL() throws {
        let json = """
        {"tag_name": "v1.3.0", "html_url": "https://github.com/bnimit/duplex/releases/tag/v1.3.0", "draft": false, "prerelease": false}
        """
        let release = try GitHubReleaseFeed.parse(Data(json.utf8))
        XCTAssertEqual(release.version, "1.3.0", "the v prefix is stripped")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/bnimit/duplex/releases/tag/v1.3.0")
    }

    func testRejectsDraftsAndPrereleases() {
        let draft = #"{"tag_name":"v9.9.9","html_url":"https://x.test/r","draft":true,"prerelease":false}"#
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data(draft.utf8)))
        let pre = #"{"tag_name":"v9.9.9","html_url":"https://x.test/r","draft":false,"prerelease":true}"#
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data(pre.utf8)))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data("not json".utf8)))
    }
}
