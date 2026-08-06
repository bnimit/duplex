import XCTest
@testable import DuplexKit

/// Scripted client: canned results, records calls.
private final class StubClient: LicenseClient, @unchecked Sendable {
    var activateResult: Result<LicenseActivation, Error> = .success(LicenseActivation(activationID: "inst-1"))
    var validateResult: Result<Bool, Error> = .success(true)
    var deactivateError: Error?
    private(set) var activateCalls = 0, validateCalls = 0, deactivateCalls = 0

    func activate(key: String, instanceName: String) async throws -> LicenseActivation {
        activateCalls += 1
        return try activateResult.get()
    }
    func validate(key: String, activationID: String?) async throws -> Bool {
        validateCalls += 1
        return try validateResult.get()
    }
    func deactivate(key: String, activationID: String) async throws {
        deactivateCalls += 1
        if let deactivateError { throw deactivateError }
    }
}

@MainActor
final class LicenseManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "duplex-license-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func manager(_ client: StubClient, now: Date = Date(timeIntervalSince1970: 1_000_000)) -> LicenseManager {
        LicenseManager(client: client, defaults: defaults, now: { now })
    }

    func testActivateStoresAndLicenses() async throws {
        let client = StubClient()
        let m = manager(client)
        try await m.activate(key: "  DUPLEX-ABCD-1234  ")
        guard case .licensed(let suffix, _) = m.state else { return XCTFail("expected licensed") }
        XCTAssertEqual(suffix, "BCD-1234")
        XCTAssertTrue(m.isLicensed)
        XCTAssertEqual(defaults.string(forKey: "license.key"), "DUPLEX-ABCD-1234")
        XCTAssertEqual(defaults.string(forKey: "license.activationID"), "inst-1")
    }

    func testActivateFailureStaysFree() async {
        let client = StubClient()
        client.activateResult = .failure(LicenseClientError.keyInvalid("activation limit reached"))
        let m = manager(client)
        do {
            try await m.activate(key: "K")
            XCTFail("expected throw")
        } catch {}
        XCTAssertEqual(m.state, .free)
        XCTAssertNil(defaults.string(forKey: "license.key"))
    }

    func testInitRestoresPersistedLicense() async throws {
        let client = StubClient()
        try await manager(client).activate(key: "DUPLEX-ABCD-1234")
        let restored = manager(client)
        XCTAssertTrue(restored.isLicensed)
    }

    func testRevalidateSkippedWhenNotDue() async throws {
        let client = StubClient()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let m = LicenseManager(client: client, defaults: defaults, now: { t0 })
        try await m.activate(key: "K-12345678")
        await m.revalidateIfDue()
        XCTAssertEqual(client.validateCalls, 0)
    }

    func testRevalidateDueAndValidRefreshesStamp() async throws {
        let client = StubClient()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let m = LicenseManager(client: client, defaults: defaults, now: { now })
        try await m.activate(key: "K-12345678")
        now = now.addingTimeInterval(LicenseManager.revalidationInterval + 60)
        await m.revalidateIfDue()
        XCTAssertEqual(client.validateCalls, 1)
        XCTAssertTrue(m.isLicensed)
        XCTAssertEqual(defaults.object(forKey: "license.lastValidated") as? Date, now)
    }

    func testRevalidateNetworkFailureKeepsLicense() async throws {
        let client = StubClient()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let m = LicenseManager(client: client, defaults: defaults, now: { now })
        try await m.activate(key: "K-12345678")
        now = now.addingTimeInterval(LicenseManager.revalidationInterval + 60)
        client.validateResult = .failure(LicenseClientError.network("offline"))
        await m.revalidateIfDue()
        XCTAssertTrue(m.isLicensed)
        XCTAssertNil(m.revocationNotice)
    }

    func testRevalidateRevokedDowngradesWithNotice() async throws {
        let client = StubClient()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let m = LicenseManager(client: client, defaults: defaults, now: { now })
        try await m.activate(key: "K-12345678")
        now = now.addingTimeInterval(LicenseManager.revalidationInterval + 60)
        client.validateResult = .success(false)
        await m.revalidateIfDue()
        XCTAssertEqual(m.state, .free)
        XCTAssertNotNil(m.revocationNotice)
        XCTAssertNil(defaults.string(forKey: "license.key"))
    }

    func testDeactivateClearsStateAndCallsServer() async throws {
        let client = StubClient()
        let m = manager(client)
        try await m.activate(key: "K-12345678")
        try await m.deactivate()
        XCTAssertEqual(client.deactivateCalls, 1)
        XCTAssertEqual(m.state, .free)
        XCTAssertNil(defaults.string(forKey: "license.key"))
    }

    func testDeactivateNetworkFailureKeepsLicense() async throws {
        let client = StubClient()
        let m = manager(client)
        try await m.activate(key: "K-12345678")
        client.deactivateError = LicenseClientError.network("offline")
        do {
            try await m.deactivate()
            XCTFail("expected throw")
        } catch {}
        XCTAssertTrue(m.isLicensed)
        XCTAssertNotNil(defaults.string(forKey: "license.key"))
    }

    func testDeactivateAlreadyGoneOnServerStillClears() async throws {
        let client = StubClient()
        let m = manager(client)
        try await m.activate(key: "K-12345678")
        client.deactivateError = LicenseClientError.keyInvalid("instance not found")
        try await m.deactivate()
        XCTAssertEqual(m.state, .free)
        XCTAssertNil(defaults.string(forKey: "license.key"))
    }
}
