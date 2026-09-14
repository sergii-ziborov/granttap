import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// Tiers differ only by linked computers; agents per computer are never counted.
@MainActor
final class SubscriptionTiersTests: XCTestCase {
    func testEveryTierIsPricedByComputersAndNeverByAgents() {
        XCTAssertEqual(SubscriptionProduct.ordered.map(\.seatLimit), [1, 5, 10])
        XCTAssertEqual(SubscriptionProduct.solo.summary, L("1 computer"))
        XCTAssertEqual(SubscriptionProduct.fleet.summary,
                       String(format: L("Up to %d computers"), 10))
        // Each tier is one App Store product; a missing one must not silently
        // resolve to another tier's limit.
        XCTAssertEqual(Set(SubscriptionProduct.allCases.map(\.rawValue)).count, 3)
        XCTAssertNil(SubscriptionOffer(id: "com.ziborov.granttap.unknown",
                                       displayName: "?", displayPrice: "?").product)
        XCTAssertEqual(SubscriptionOffer(id: "com.ziborov.granttap.unknown",
                                         displayName: "?", displayPrice: "?").seatLimit, 0)
    }

    func testThePaywallShowsTheLadderSmallestFirst() {
        let offers = [
            SubscriptionOffer(id: SubscriptionProduct.fleet.rawValue,
                              displayName: "Fleet", displayPrice: "$5.99"),
            SubscriptionOffer(id: SubscriptionProduct.solo.rawValue,
                              displayName: "Solo", displayPrice: "$1.99"),
            SubscriptionOffer(id: SubscriptionProduct.personal.rawValue,
                              displayName: "Personal", displayPrice: "$3.99"),
        ]
        let view = SubscriptionView(store: SubscriptionStore(startObserving: false),
                                    offers: offers)
        XCTAssertEqual(view.offersForDisplay.map(\.seatLimit), [1, 5, 10])
        XCTAssertFalse(view.isCurrent(offers[0]), "no entitlement means no current plan")
        let frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.view.subviews.isEmpty)
    }
}
