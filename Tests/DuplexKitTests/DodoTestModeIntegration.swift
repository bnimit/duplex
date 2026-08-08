import XCTest
@testable import DuplexKit

/// Manual dress rehearsal against Dodo's TEST-mode API with the real client.
/// Skipped unless DODO_TEST_KEY is set:
///   DODO_TEST_KEY=<test key> swift test --filter DodoTestModeIntegration
final class DodoTestModeIntegration: XCTestCase {
    func testFullLicenseLifecycle() async throws {
        guard let key = ProcessInfo.processInfo.environment["DODO_TEST_KEY"], !key.isEmpty else {
            throw XCTSkip("Set DODO_TEST_KEY to run the test-mode integration")
        }
        let client = DodoLicenseClient(base: DodoLicenseClient.testBase)

        // 1. First activation (a customer's first Mac).
        let first = try await client.activate(key: key, instanceName: "E2E Mac 1")
        print("E2E: activation 1 id =", first.activationID)

        // 2. Validate while active.
        let valid = try await client.validate(key: key, activationID: first.activationID)
        XCTAssertTrue(valid, "freshly activated key must validate")
        print("E2E: validate while active = true")

        // 3. Second activation (the customer's second Mac; limit is 2).
        let second = try await client.activate(key: key, instanceName: "E2E Mac 2")
        print("E2E: activation 2 id =", second.activationID)

        // 4. Third activation should hit the limit IF the product is
        //    configured with activation limit 2.
        do {
            let third = try await client.activate(key: key, instanceName: "E2E Mac 3")
            print("E2E: WARNING third activation SUCCEEDED (id \(third.activationID));")
            print("E2E: the test product has no activation limit of 2 configured")
            try await client.deactivate(key: key, activationID: third.activationID)
        } catch let error as LicenseClientError {
            if case .keyInvalid(let message) = error {
                print("E2E: third activation correctly refused:", message)
            } else {
                throw error
            }
        }

        // 5. Deactivate both (moving off a Mac).
        try await client.deactivate(key: key, activationID: second.activationID)
        try await client.deactivate(key: key, activationID: first.activationID)
        print("E2E: both activations deactivated")

        // 6. Reactivate to prove a freed slot is reusable, then clean up.
        let again = try await client.activate(key: key, instanceName: "E2E Mac 1 again")
        print("E2E: reactivation id =", again.activationID)
        try await client.deactivate(key: key, activationID: again.activationID)
        print("E2E: lifecycle complete")
    }
}
