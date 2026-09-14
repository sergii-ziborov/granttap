import XCTest
@testable import GrantTapWatch

/// The shared plural helper is compiled into the watch too, so the watch
/// proves it counts the way each language does.
final class WatchPluralTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocale.storageKey)
        super.tearDown()
    }

    func testEnglishAndRussianForms() {
        UserDefaults.standard.removeObject(forKey: AppLocale.storageKey)
        XCTAssertEqual(LPlural(1, one: "%d process", many: "%d processes"), "1 process")
        XCTAssertEqual(LPlural(7, one: "%d process", many: "%d processes"), "7 processes")
        UserDefaults.standard.set("ru", forKey: AppLocale.storageKey)
        XCTAssertEqual(LPlural(1, one: "%d process", many: "%d processes"), "1 процесс")
        XCTAssertEqual(LPlural(3, one: "%d process", many: "%d processes"), "3 процесса")
        XCTAssertEqual(LPlural(12, one: "%d process", many: "%d processes"), "12 процессов")
        XCTAssertEqual(LPlural(22, one: "%d chat", many: "%d chats"), "22 чата")
    }
}
