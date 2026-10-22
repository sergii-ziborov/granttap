import XCTest
@testable import GrantTap

@MainActor
final class SandboxReviewCatalogTests: XCTestCase {
    func testExplicitPurchaseOptionsReportCatalogErrorsWithoutRevokingFreeSandboxAccess() async {
        let error = URLError(.notConnectedToInternet)
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            betaAccessLoader: { true }, productLoader: { throw error })
        await store.start()
        XCTAssertEqual(store.license, .testFlight)
        XCTAssertNil(store.lastError, "Free access must not wait for a purchase catalog at startup.")

        await store.loadPurchaseOptions()

        XCTAssertEqual(store.lastError, error.localizedDescription)
        XCTAssertEqual(store.license, .testFlight)
        XCTAssertTrue(store.license.permitsLocalControl)
    }

    func testExplicitCatalogLoadingDoesNotCreateAPurchaseOrRevokeAnExistingLicense() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            betaAccessLoader: { true }, productLoader: { [] })
        await store.start()
        await store.loadPurchaseOptions()
        XCTAssertNil(store.product)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.purchasing)
        XCTAssertEqual(store.license, .testFlight)
    }
}
