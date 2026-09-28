import XCTest
@testable import GrantTap

final class DesktopLicenseTests: XCTestCase {
    let bundleID = "com.ziborov.granttap"

    func testProductionRequiresVerifiedUnrevokedMacPurchase() {
        let valid = DesktopPurchaseEvidence(identifier: DesktopLicense.productID,
                                           verified: true, revoked: false, nonConsumable: true)
        XCTAssertEqual(resolve([valid]), .purchased)
        XCTAssertTrue(resolve([valid]).permitsOwnRelay)
        XCTAssertEqual(resolve([]), .notPurchased)
        XCTAssertFalse(resolve([]).permitsLocalControl)
        XCTAssertFalse(resolve([]).permitsOwnRelay)
        for invalid in [
            DesktopPurchaseEvidence(identifier: valid.identifier, verified: false,
                                    revoked: false, nonConsumable: true),
            DesktopPurchaseEvidence(identifier: valid.identifier, verified: true,
                                    revoked: true, nonConsumable: true),
            DesktopPurchaseEvidence(identifier: valid.identifier, verified: true,
                                    revoked: false, nonConsumable: false),
            DesktopPurchaseEvidence(identifier: SubscriptionProduct.solo.rawValue, verified: true,
                                    revoked: false, nonConsumable: true),
        ] {
            XCTAssertEqual(resolve([invalid]), .notPurchased)
        }
    }

    func testEvaluationIsExplicitAndDoesNotGrantProductionSelfHosting() {
        let evaluation = DesktopLicense.resolve([], distribution: .inAppUnlock,
            bundleID: bundleID, evaluationAllowed: true)
        XCTAssertEqual(evaluation, .evaluation)
        XCTAssertTrue(evaluation.permitsLocalControl)
        XCTAssertFalse(evaluation.permitsOwnRelay)
        XCTAssertFalse(DesktopLicense.checking.permitsLocalControl)
    }

    func testSeparatePaidDownloadUsesItsOwnVerifiedAppTransaction() {
        let bundleID = "com.ziborov.granttap.mac"
        let receipt = DesktopPurchaseEvidence(identifier: bundleID, verified: true,
                                              revoked: false, nonConsumable: false)
        XCTAssertEqual(DesktopLicense.resolve([receipt], distribution: .paidDownload,
            bundleID: bundleID, evaluationAllowed: false), .purchased)
        XCTAssertEqual(resolve([receipt]), .notPurchased)
        XCTAssertEqual(DesktopLicense.resolve([
            DesktopPurchaseEvidence(identifier: "another.app", verified: true,
                                    revoked: false, nonConsumable: false)
        ], distribution: .paidDownload, bundleID: bundleID, evaluationAllowed: false), .notPurchased)
        XCTAssertEqual(DesktopLicense.resolve([
            DesktopPurchaseEvidence(identifier: self.bundleID, verified: true,
                                    revoked: false, nonConsumable: false)
        ], distribution: .paidDownload, bundleID: self.bundleID, evaluationAllowed: false), .notPurchased)
    }

    private func resolve(_ evidence: [DesktopPurchaseEvidence]) -> DesktopLicense {
        DesktopLicense.resolve(evidence, distribution: .inAppUnlock,
                               bundleID: bundleID, evaluationAllowed: false)
    }
}
