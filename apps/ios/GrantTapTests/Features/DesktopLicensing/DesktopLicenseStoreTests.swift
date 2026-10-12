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

    func testVerifiedBetaExpirySurvivesPurchaseCatalogFailure() async {
        let expiry = Date().addingTimeInterval(60 * 60)
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { throw URLError(.notConnectedToInternet) },
            betaExpiryLoader: { expiry })
        await store.refresh()
        XCTAssertEqual(store.license, .betaTrial(expiresAt: expiry))
        XCTAssertTrue(store.license.permitsLocalControl)
        XCTAssertNotNil(store.lastError)
    }

    func testExplicitTestFlightVerificationRecoversUnavailableStartupEvidence() async {
        let expiry = Date().addingTimeInterval(60 * 60)
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaExpiryLoader: { nil },
            betaRefreshLoader: { expiry })
        await store.refresh()
        XCTAssertEqual(store.license, .notPurchased)
        await store.verifyBetaTrial()
        XCTAssertEqual(store.license, .betaTrial(expiresAt: expiry))
        await store.refresh()
        XCTAssertEqual(store.license, .betaTrial(expiresAt: expiry))
    }

    func testUnavailableTestFlightVerificationDoesNotGrantALicense() async {
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaExpiryLoader: { nil },
            betaRefreshLoader: { nil })
        await store.refresh()
        await store.verifyBetaTrial()
        XCTAssertEqual(store.license, .notPurchased)
        XCTAssertNotNil(store.lastError)
    }

    func testTestFlightVerificationFailurePreservesPreviouslyVerifiedTrial() async {
        let expiry = Date().addingTimeInterval(60 * 60)
        let store = DesktopLicenseStore(evaluationAllowed: false, observe: false,
            evidenceLoader: { [] }, betaExpiryLoader: { expiry },
            betaRefreshLoader: { throw URLError(.notConnectedToInternet) })
        await store.refresh()
        await store.verifyBetaTrial()
        XCTAssertEqual(store.license, .betaTrial(expiresAt: expiry))
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
