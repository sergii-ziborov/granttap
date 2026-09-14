import XCTest
@testable import GrantTap

/// One control in one place. The composer used to hide its send arrow whenever
/// the field was empty and put an unattached "Done" above the keyboard instead,
/// so the button moved depending on what you had typed.
final class ComposerActionTests: XCTestCase {
    func testTypingTurnsTheControlIntoSend() {
        XCTAssertEqual(ComposerAction.resolve(hasContent: true, isFocused: true), .send)
        XCTAssertEqual(
            ComposerAction.resolve(hasContent: true, isFocused: false),
            .send,
            "dictation fills the field without focusing it"
        )
    }

    func testAnEmptyFocusedFieldOffersToGetOutOfTheWay() {
        XCTAssertEqual(ComposerAction.resolve(hasContent: false, isFocused: true), .dismiss)
    }

    func testAnIdleComposerShowsNoControlAtAll() {
        XCTAssertEqual(
            ComposerAction.resolve(hasContent: false, isFocused: false),
            .none,
            "a resting composer must not show a button that does nothing useful"
        )
    }

    func testEveryStateKeepsTheControlInTheSamePlace() {
        // The control occupies its slot whenever it exists, so the text field
        // never resizes underneath the user mid-sentence.
        for action in [ComposerAction.send, .dismiss] {
            XCTAssertTrue(action.isVisible)
        }
        XCTAssertFalse(ComposerAction.none.isVisible)
    }

    func testWhitespaceIsNotContent() {
        XCTAssertEqual(ComposerAction.resolve(text: "   \n ", attachments: 0, isFocused: true), .dismiss)
        XCTAssertEqual(ComposerAction.resolve(text: "  hi ", attachments: 0, isFocused: true), .send)
        XCTAssertEqual(
            ComposerAction.resolve(text: "", attachments: 1, isFocused: false),
            .send,
            "an attachment alone is a message worth sending"
        )
    }
}
