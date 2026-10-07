import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class ProductInformationTests: XCTestCase {
    func testAllCustomerDocumentsAreBundledInBothLanguages() throws {
        for language in ["en", "ru"] {
            for information in ProductInformation.allCases where information != .about {
                let document = try ProductDocument.load(information, language: language)
                XCTAssertFalse(document.title.isEmpty)
                XCTAssertFalse(document.intro.isEmpty)
                XCTAssertGreaterThanOrEqual(document.sections.count, 3)
                XCTAssertTrue(document.updated.hasPrefix("2026-"))
                for section in document.sections {
                    XCTAssertFalse(section.heading.isEmpty)
                    XCTAssertFalse((section.paragraphs ?? []) + (section.bullets ?? []) == [] &&
                        (section.links ?? []).isEmpty)
                    for link in section.links ?? [] { XCTAssertNotNil(link.url) }
                }
            }
        }
    }

    func testTermsDescribeAppleBillingAndIndependentMacUse() throws {
        let terms = try ProductDocument.load(.terms, language: "en")
        let text = terms.sections.flatMap { ($0.paragraphs ?? []) + ($0.bullets ?? []) }.joined()
        XCTAssertTrue(text.contains("Standard Licensed Application"))
        XCTAssertTrue(text.contains("$39.99"))
        XCTAssertTrue(text.contains("optional auto-renewable subscription"))
        XCTAssertTrue(text.contains("self-hosted"))
    }

    func testHelpHasTheActualDeviceNetworkPathsAndPurchaseRecovery() throws {
        let help = try ProductDocument.load(.help, language: "en")
        let text = help.sections.flatMap { ($0.paragraphs ?? []) + ($0.bullets ?? []) }.joined()
        XCTAssertTrue(text.contains("Help → GrantTap Help"))
        XCTAssertTrue(text.contains("Devices → Connect iPhone or iPad"))
        XCTAssertTrue(text.contains("Account Mesh exists"))
        XCTAssertTrue(text.contains("Connect a computer by link"))
        XCTAssertTrue(text.contains("Restore purchases"))
    }

    func testDocumentLinksResolveOnlyToSafePublicDestinations() {
        let relative = ProductDocument.DocumentLink(label: "Terms", href: "/terms")
        XCTAssertEqual(relative.url?.absoluteString, "https://granttap.com/terms")
        XCTAssertNotNil(ProductDocument.DocumentLink(label: "Contact", href: "mailto:example@example.com").url)
        XCTAssertNil(ProductDocument.DocumentLink(label: "Invalid", href: "javascript:alert(1)").url)
    }

    func testMissingDocumentReportsAnErrorAndUnknownLanguageUsesEnglish() throws {
        XCTAssertThrowsError(try ProductDocument.load(.about))
        XCTAssertEqual(try ProductDocument.load(.terms, language: "fr"),
                       try ProductDocument.load(.terms, language: "en"))
    }

    func testNativeMenusOfferAboutAndWorkingHelpDestinations() {
        let about = ProductInformationMenus.aboutMenu(open: { _ in })
        XCTAssertEqual(about.identifier, .about)
        XCTAssertEqual(about.children.map(\.title), [ProductInformation.about.title])
        let help = ProductInformationMenus.helpMenu(open: { _ in })
        XCTAssertEqual(help.identifier, .help)
        let entries: [ProductInformation] = [.help, .pricing, .terms, .privacy, .licenses]
        XCTAssertEqual(help.children.map(\.title), entries.map(\.title))
        XCTAssertEqual(Set(help.children.compactMap { ($0 as? UIAction)?.identifier.rawValue }).count, 5)
    }

    func testMenuRequestsDeliverTheExactDestinationToTheMainWindow() {
        let center = NotificationCenter()
        var received: [ProductInformation] = []
        let observer = center.addObserver(forName: ProductInformation.requested, object: nil, queue: nil) {
            if let item = $0.object as? ProductInformation { received.append(item) }
        }
        defer { center.removeObserver(observer) }
        for item in ProductInformation.allCases { item.open(in: center) }
        XCTAssertEqual(received, ProductInformation.allCases)
    }

    func testBuiltInDocumentsAndAboutDrawWithoutConnection() {
        for item in ProductInformation.allCases {
            RenderProbe.render(CompatNavigationStack { ProductInformationView(information: item) }
                .environmentObject(AppModel()), height: 1_100)
        }
    }
}
