import XCTest
@testable import DuplexKit

final class CodesignerTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testAdhocSignReplacesSignature() throws {
        let copy = tmp.appendingPathComponent("ls")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: copy)
        XCTAssertEqual(Codesigner.signatureKind(copy), "signed", "Apple's own signature before re-signing")
        try Codesigner.adhocSign(copy)
        XCTAssertEqual(Codesigner.signatureKind(copy), "adhoc")
    }

    func testSignatureKindOfUnsignedFileIsNil() throws {
        let script = tmp.appendingPathComponent("s.sh")
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertNil(Codesigner.signatureKind(script))
    }

    func testAdhocSignFailureThrows() {
        XCTAssertThrowsError(try Codesigner.adhocSign(tmp.appendingPathComponent("missing"))) { error in
            guard case WrapperGeneratorError.codesignFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }
}
