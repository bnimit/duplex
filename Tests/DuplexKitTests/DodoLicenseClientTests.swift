import XCTest
@testable import DuplexKit

/// Transport stub for the JSON path: records the request, returns a canned response.
private struct StubJSONTransport: HTTPTransport {
    let response: (Data, Int)
    let onPost: (@Sendable (URL, [String: String]) -> Void)?
    init(json: String, status: Int = 200, onPost: (@Sendable (URL, [String: String]) -> Void)? = nil) {
        self.response = (Data(json.utf8), status)
        self.onPost = onPost
    }
    func post(url: URL, form: [String: String]) async throws -> (Data, Int) {
        XCTFail("Dodo client must use JSON, not form encoding")
        return response
    }
    func postJSON(url: URL, json: [String: String]) async throws -> (Data, Int) {
        onPost?(url, json)
        return response
    }
}

private struct FailingJSONTransport: HTTPTransport {
    func post(url: URL, form: [String: String]) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet)
    }
    func postJSON(url: URL, json: [String: String]) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet)
    }
}

final class DodoLicenseClientTests: XCTestCase {
    func testActivateSuccessParsesInstanceID() async throws {
        let client = DodoLicenseClient(transport: StubJSONTransport(
            json: #"{"id": "lki_123", "business_id": "b1", "name": "Test Mac"}"#,
            status: 201,
            onPost: { url, body in
                XCTAssertEqual(url.absoluteString, "https://live.dodopayments.com/licenses/activate")
                XCTAssertEqual(body["license_key"], "KEY-1")
                XCTAssertEqual(body["name"], "Test Mac")
            }))
        let activation = try await client.activate(key: "KEY-1", instanceName: "Test Mac")
        XCTAssertEqual(activation, LicenseActivation(activationID: "lki_123"))
    }

    func testActivateLimitReachedThrowsKeyInvalid() async {
        let client = DodoLicenseClient(transport: StubJSONTransport(
            json: #"{"message": "license key activation limit reached"}"#, status: 422))
        do {
            _ = try await client.activate(key: "K", instanceName: "Mac")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            XCTAssertEqual(e, .keyInvalid("license key activation limit reached"))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testActivateUnknownKeyThrowsKeyInvalid() async {
        let client = DodoLicenseClient(transport: StubJSONTransport(json: "{}", status: 404))
        do {
            _ = try await client.activate(key: "K", instanceName: "Mac")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            XCTAssertEqual(e, .keyInvalid("License key not found."))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testActivateSuccessWithoutIDMapsToNetworkError() async {
        let client = DodoLicenseClient(transport: StubJSONTransport(json: "{}", status: 201))
        do {
            _ = try await client.activate(key: "K", instanceName: "Mac")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .network = e else { return XCTFail("expected .network, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testValidateParsesValidTrueAndFalse() async throws {
        let valid = DodoLicenseClient(transport: StubJSONTransport(
            json: #"{"valid": true}"#,
            onPost: { url, body in
                XCTAssertEqual(url.absoluteString, "https://live.dodopayments.com/licenses/validate")
                XCTAssertEqual(body["license_key_instance_id"], "lki_123")
            }))
        let revoked = DodoLicenseClient(transport: StubJSONTransport(json: #"{"valid": false}"#))
        let isValid = try await valid.validate(key: "K", activationID: "lki_123")
        let isRevoked = try await revoked.validate(key: "K", activationID: "lki_123")
        XCTAssertTrue(isValid)
        XCTAssertFalse(isRevoked)
    }

    func testValidateNon200MapsToNetworkError() async {
        let client = DodoLicenseClient(transport: StubJSONTransport(json: "oops", status: 500))
        do {
            _ = try await client.validate(key: "K", activationID: nil)
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .network = e else { return XCTFail("expected .network, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testDeactivateSuccess() async throws {
        let client = DodoLicenseClient(transport: StubJSONTransport(
            json: "",
            onPost: { url, body in
                XCTAssertEqual(url.absoluteString, "https://live.dodopayments.com/licenses/deactivate")
                XCTAssertEqual(body["license_key_instance_id"], "lki_123")
            }))
        try await client.deactivate(key: "K", activationID: "lki_123")
    }

    func testDeactivateGoneInstanceThrowsKeyInvalid() async {
        let client = DodoLicenseClient(transport: StubJSONTransport(json: "{}", status: 403))
        do {
            try await client.deactivate(key: "K", activationID: "gone")
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .keyInvalid = e else { return XCTFail("expected .keyInvalid, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testTransportFailureMapsToNetworkError() async {
        let client = DodoLicenseClient(transport: FailingJSONTransport())
        do {
            _ = try await client.validate(key: "K", activationID: nil)
            XCTFail("expected throw")
        } catch let e as LicenseClientError {
            guard case .network = e else { return XCTFail("expected .network, got \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }
}
