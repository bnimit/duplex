import XCTest
@testable import DuplexKit

final class InstallMethodTests: XCTestCase {
    func testDetectsHomebrewOnAppleSilicon() {
        let method = InstallMethod.detect { $0 == "/opt/homebrew/Caskroom/duplex" }
        XCTAssertEqual(method, .homebrew)
    }

    func testDetectsHomebrewOnIntel() {
        let method = InstallMethod.detect { $0 == "/usr/local/Caskroom/duplex" }
        XCTAssertEqual(method, .homebrew)
    }

    func testFallsBackToDirectDownload() {
        XCTAssertEqual(InstallMethod.detect { _ in false }, .direct)
    }

    func testDoesNotMatchAnUnrelatedCaskroomEntry() {
        let method = InstallMethod.detect { $0 == "/opt/homebrew/Caskroom/something-else" }
        XCTAssertEqual(method, .direct)
    }
}
