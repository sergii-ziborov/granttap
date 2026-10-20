import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionReviewCaptureTests: XCTestCase {
    func testNativePaywallOffersShowEligibleTrialAndKnownComputerLimits() throws {
        let prices = ["$4.99", "$7.99", "$13.99"]
        let store = SubscriptionStore(startObserving: false, productLoader: { [] },
            currentAccountID: { "12345678-1234-4123-8123-123456789012" })
        for (product, price) in zip(SubscriptionProduct.ordered, prices) {
            let offer = SubscriptionOffer(id: product.rawValue, displayName: product.summary,
                displayPrice: price, hasSevenDayTrial: true)
            let screen = SubscriptionView(store: store, offers: [offer])
            XCTAssertEqual(screen.offersForDisplay.first?.seatLimit, product.seatLimit)
            let image = DesignSnapshotTests.render(NavigationView { screen })
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 8_000)
            let capture = XCTAttachment(image: image)
            capture.name = "Personal \(product.seatLimit) launch review"
            capture.lifetime = .keepAlways
            add(capture)
            if let directory = ProcessInfo.processInfo.environment["GRANTTAP_COMMERCE_CAPTURE_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("personal-\(product.seatLimit)-review.png"))
            }
        }
    }
}
