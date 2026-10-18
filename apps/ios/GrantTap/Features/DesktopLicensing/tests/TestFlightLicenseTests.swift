import XCTest
@testable import GrantTap

final class TestFlightLicenseTests: XCTestCase {
    func testVerifiedTestFlightAllowsLocalAndOwnRelayWithoutPurchaseOrSubscription() {
        for distribution in [DesktopLicenseDistribution.inAppUnlock, .paidDownload] {
            let access = DesktopLicense.resolve([], distribution: distribution,
                bundleID: "com.ziborov.granttap", evaluationAllowed: false,
                testFlightVerified: true)
            XCTAssertTrue(access.permitsLocalControl)
            XCTAssertTrue(access.permitsOwnRelay)
            XCTAssertNotEqual(access, .purchased)
        }
    }

    func testProductionWithoutPurchaseRemainsLocked() {
        let access = DesktopLicense.resolve([], distribution: .inAppUnlock,
            bundleID: "com.ziborov.granttap", evaluationAllowed: false,
            testFlightVerified: false)
        XCTAssertFalse(access.permitsLocalControl)
        XCTAssertFalse(access.permitsOwnRelay)
    }
}
