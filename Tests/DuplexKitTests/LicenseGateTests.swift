import XCTest
@testable import DuplexKit

final class LicenseGateTests: XCTestCase {
    func testFirstInstanceIsFree() {
        XCTAssertTrue(LicenseGate.canCreate(existingCount: 0, isRegeneration: false, licensed: false))
    }
    func testSecondInstanceRequiresLicense() {
        XCTAssertFalse(LicenseGate.canCreate(existingCount: 1, isRegeneration: false, licensed: false))
        XCTAssertFalse(LicenseGate.canCreate(existingCount: 3, isRegeneration: false, licensed: false))
    }
    func testLicensedIsUnlimited() {
        XCTAssertTrue(LicenseGate.canCreate(existingCount: 0, isRegeneration: false, licensed: true))
        XCTAssertTrue(LicenseGate.canCreate(existingCount: 99, isRegeneration: false, licensed: true))
    }
    func testRegenerationIsNeverGated() {
        XCTAssertTrue(LicenseGate.canCreate(existingCount: 1, isRegeneration: true, licensed: false))
        XCTAssertTrue(LicenseGate.canCreate(existingCount: 5, isRegeneration: true, licensed: false))
    }
}
