import UIKit
import XCTest
@testable import GrantTap

final class ProjectControllerDeviceTests: XCTestCase {
    func testMacControllerUsesMacNameAndComputerIcon() {
        let device = ProjectControllerDevice(idiom: .mac)
        XCTAssertEqual(device.titleKey, "This Mac")
        XCTAssertEqual(device.symbol, "desktopcomputer")
    }

    func testTabletControllerUsesIPadNameAndIcon() {
        let device = ProjectControllerDevice(idiom: .pad)
        XCTAssertEqual(device.titleKey, "This iPad")
        XCTAssertEqual(device.symbol, "ipad")
    }

    func testPhoneControllerRetainsIPhoneNameAndIcon() {
        let device = ProjectControllerDevice(idiom: .phone)
        XCTAssertEqual(device.titleKey, "This iPhone")
        XCTAssertEqual(device.symbol, "iphone.gen3")
    }

    func testUnknownControllerDoesNotPretendToBeAPhone() {
        let device = ProjectControllerDevice(idiom: .unspecified)
        XCTAssertEqual(device.titleKey, "This device")
        XCTAssertEqual(device.symbol, "rectangle")
    }
}
