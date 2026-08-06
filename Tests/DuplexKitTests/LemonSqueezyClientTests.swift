import XCTest
@testable import DuplexKit

/// Transport stub: records the request, returns a canned response.
private struct StubTransport: HTTPTransport {
    let response: (Data, Int)
    let onPost: (@Sendable (URL, [String: String]) -> Void)?
    init(json: String, status: Int = 200, onPost: (@Sendable (URL, [String: String]) -> Void)? = nil) {
        self.response = (Data(json.utf8), status)
        self.onPost = onPost
    }
    func post(url: URL, form: [String: String]) async throws -> (Data, Int) {
        onPost?(url, form)
        return response
    }
}

private struct FailingTransport: HTTPTransport {
    func post(url: URL, form: [String: String]) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet)
    }
}

final class LemonSqueezyClientTests: XCTestCase {
    func testActivateSuccessParsesActivationID() async throws {
        let client = LemonSqueezyClient(transport: StubTransport(
            json: #"{"activated": true, "instance": {"id": "inst-123"}}"#,
            onPost: { url, form in
                XCTAssertEqual(url.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/activate")
                XCTAssertEqual(form["license_key"], "KEY-1")
                XCTAssertEqual(form["instance_name"], "Test Mac")
            }))
        let activation = try await client.activate(key: "KEY-1", instanceName: "Test Mac")
        XCTAssertEqual(activation, LicenseActivation(activationID: "inst-123"))
    }
    func testActivateRejectionThrowsKeyInvalidWithMessage() async {
        let client = LemonSqueezyClient(transport: StubTransport(
            json: #"{"activated": false, "error": "activation limit reached"}"#, status: 400))
        do {
            _ = try await client.activate(key: "KEY-1", instanceName: "Mac")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            XCTAssertEqual(e, .keyInvalid("activation limit reached"))
        } catch { XCTFail("wrong error: \(error)") }
    }
    func testValidateParsesValidTrueAndFalse() async throws {
        let valid = LemonSqueezyClient(transport: StubTransport(json: #"{"valid": true}"#))
        let revoked = LemonSqueezyClient(transport: StubTransport(json: #"{"valid": false}"#, status: 404))
        let isValid = try await valid.validate(key: "K", activationID: "i")
        let isRevoked = try await revoked.validate(key: "K", activationID: "i")
        XCTAssertTrue(isValid)
        XCTAssertFalse(isRevoked)
    }
    func testTransportFailureMapsToNetworkError() async {
        let client = LemonSqueezyClient(transport: FailingTransport())
        do {
            _ = try await client.validate(key: "K", activationID: nil)
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .network = e else { return XCTFail("expected .network, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }
    func testGarbageResponseMapsToNetworkError() async {
        let client = LemonSqueezyClient(transport: StubTransport(json: "<html>502</html>", status: 502))
        do {
            _ = try await client.activate(key: "K", instanceName: "Mac")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .network = e else { return XCTFail("expected .network, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }
}
