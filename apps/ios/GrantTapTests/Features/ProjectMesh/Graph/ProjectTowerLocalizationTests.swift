import XCTest
@testable import GrantTap

final class ProjectTowerLocalizationTests: XCTestCase {
    private var savedLanguage: String?

    override func setUp() {
        super.setUp()
        savedLanguage = getenv("GRANTTAP_TEST_LANGUAGE").map { String(cString: $0) }
    }

    override func tearDown() {
        if let savedLanguage { setenv("GRANTTAP_TEST_LANGUAGE", savedLanguage, 1) }
        else { unsetenv("GRANTTAP_TEST_LANGUAGE") }
        super.tearDown()
    }

    func testEnglishControlsAndReportedSectionCountsUseTheEnglishKeys() {
        setenv("GRANTTAP_TEST_LANGUAGE", "en", 1)
        XCTAssertEqual(L("Zoom in"), "Zoom in")
        XCTAssertEqual(L("Focus selected tower"), "Focus selected tower")
        XCTAssertEqual(LPlural(1, one: "%d reported section", many: "%d reported sections"), "1 reported section")
        XCTAssertEqual(LPlural(36, one: "%d reported section", many: "%d reported sections"), "36 reported sections")
    }

    func testRussianCameraActionsAndOneFewManySectionFormsAreTranslated() {
        setenv("GRANTTAP_TEST_LANGUAGE", "ru", 1)
        XCTAssertEqual(L("Zoom in"), "Увеличить")
        XCTAssertEqual(L("Orbit"), "Вращение")
        XCTAssertEqual(L("Pan"), "Перемещение")
        XCTAssertEqual(L("Observed source"), "Данные исходного кода")
        for (count, value) in [1: "1 секция в отчёте", 2: "2 секции в отчёте", 5: "5 секций в отчёте",
                               11: "11 секций в отчёте", 22: "22 секции в отчёте", 100: "100 секций в отчёте"] {
            XCTAssertEqual(LPlural(count, one: "%d reported section", many: "%d reported sections"), value)
        }
    }
}
