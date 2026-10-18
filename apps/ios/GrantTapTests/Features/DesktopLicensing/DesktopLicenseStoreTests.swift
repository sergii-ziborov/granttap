import XCTest
@testable import GrantTap

@MainActor
final class DesktopLicenseStoreTests: XCTestCase {
    func testRefreshDoesNotTrustPreviouslyGrantedStateAfterRevocation() async {
        var evidence = [DesktopPurchaseEvidence(identifier: DesktopLicense.productID,
            verified: true, revoked: false, nonConsumable: true)]
        let store = DesktopLicenseStore(distribution: .inAppUnlock, bundleID: "com.ziborov.granttap",
            evaluationAllowed: false, observe: false, evidenceLoader: { evidence }, productLoader: { [] })
        await store.start()
        XCTAssertEqual(store.license, .purchased)
        evidence = []
        await store.refresh()
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertFalse(store.license.permitsOwnRelay)
    }

    func testVerifiedCachedPurchaseSurvivesUnavailableStoreCatalog() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false, evidenceLoader: {
            [DesktopPurchaseEvidence(identifier: DesktopLicense.productID,
                verified: true, revoked: false, nonConsumable: true)]
        }, productLoader: { throw URLError(.notConnectedToInternet) })
        await store.start()
        XCTAssertEqual(store.license, .purchased)
        XCTAssertNil(store.product)
        XCTAssertNotNil(store.lastError)
    }

    func testReadFailureDoesNotGrantProductionOrSelfHostingLicense() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { throw URLError(.notConnectedToInternet) })
        await store.refresh()
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertNotNil(store.lastError)
        let evaluation = DesktopLicenseStore(evaluationAllowed: true, observe: false,
            evidenceLoader: { throw URLError(.notConnectedToInternet) })
        await evaluation.refresh()
        XCTAssertEqual(evaluation.license, .evaluation)
        XCTAssertFalse(evaluation.license.permitsOwnRelay)
    }

    func testVerifiedTestFlightAccessDoesNotWaitForPurchaseCatalogOrReceipts() async {
        var reads = 0
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { reads += 1; throw URLError(.notConnectedToInternet) },
            betaAccessLoader: { true }, productLoader: { reads += 1; return [] })
        await store.start()
        XCTAssertEqual(store.license, .testFlight)
        XCTAssertTrue(store.license.permitsLocalControl)
        XCTAssertTrue(store.license.permitsOwnRelay)
        XCTAssertEqual(reads, 0)
        XCTAssertNil(store.lastError)
    }

    func testExplicitTestFlightVerificationRecoversUnavailableStartupEvidence() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaAccessLoader: { false },
            betaRefreshLoader: { true })
        await store.refresh()
        XCTAssertEqual(store.license, .notPurchased)
        await store.verifyTestFlightAccess()
        XCTAssertEqual(store.license, .testFlight)
        await store.refresh()
        XCTAssertEqual(store.license, .testFlight)
    }

    func testUnavailableTestFlightVerificationDoesNotGrantALicense() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaAccessLoader: { false },
            betaRefreshLoader: { false })
        await store.refresh()
        await store.verifyTestFlightAccess()
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertNotNil(store.lastError)
    }

    func testTestFlightVerificationFailurePreservesPreviouslyVerifiedAccess() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaAccessLoader: { true },
            betaRefreshLoader: { throw URLError(.notConnectedToInternet) })
        await store.refresh()
        await store.verifyTestFlightAccess()
        XCTAssertEqual(store.license, .testFlight)
        XCTAssertNotNil(store.lastError)
    }

    func testRestoreRechecksEvidenceAndDoesNotCreateReceipt() async {
        var synced = 0
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, productLoader: { [] }, storeSync: { synced += 1 })
        await store.restore()
        XCTAssertEqual(synced, 1)
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertFalse(store.purchasing)
        await store.purchase()
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.license, .notPurchased)
    }

    func testPaidDownloadDoesNotLoadAnInAppUnlock() async {
        var loaded = false
        let store = DesktopLicenseStore(distribution: .paidDownload, bundleID: "com.ziborov.granttap.mac",
            evaluationAllowed: false, observe: false, evidenceLoader: {
                [DesktopPurchaseEvidence(identifier: "com.ziborov.granttap.mac", verified: true,
                    revoked: false, nonConsumable: false)]
            }, productLoader: { loaded = true; return [] })
        await store.start()
        XCTAssertEqual(store.license, .purchased)
        XCTAssertFalse(loaded)
        await store.purchase()
        XCTAssertNotNil(store.lastError)
    }

    func testRestoreFailureDoesNotEraseVerifiedPurchaseOrLeaveBusyState() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false, evidenceLoader: {
            [DesktopPurchaseEvidence(identifier: DesktopLicense.productID,
                verified: true, revoked: false, nonConsumable: true)]
        }, storeSync: { throw URLError(.notConnectedToInternet) })
        await store.refresh()
        await store.restore()
        XCTAssertEqual(store.license, .purchased)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.purchasing)
    }
}
