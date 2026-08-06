import XCTest
@testable import DuplexKit

final class URLSchemeRouterTests: XCTestCase {
    func testCurrentHandlerForHTTPSExists() {
        // Every Mac has a default browser; https must resolve to some app.
        let handler = URLSchemeRouter.currentHandler(forScheme: "https")
        XCTAssertNotNil(handler)
        XCTAssertEqual(handler?.pathExtension, "app")
    }

    func testCurrentHandlerForNonsenseSchemeIsNil() {
        XCTAssertNil(URLSchemeRouter.currentHandler(forScheme: "duplex-definitely-not-registered-xyz"))
    }
}
