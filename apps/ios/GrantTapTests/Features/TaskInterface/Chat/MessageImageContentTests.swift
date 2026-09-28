import XCTest
@testable import GrantTap

final class MessageImageContentTests: XCTestCase {
    func testAllFifteenLinkedPicturesReplaceTheirListAtTheMessagePosition() {
        let pictures = (0..<15).map { index in
            MessageImageAttachment(id: "image-\(index)", name: "badge-\(index).png",
                markdown: "[badge-\(index).png](/workspace/badge-\(index).png)")
        }
        let text = "Generated all badges:\n\n" + pictures.map { "- \($0.markdown)" }.joined(separator: "\n") + "\n\nDone."
        XCTAssertEqual(MessageImageContent.parts(text, images: pictures), [
            .text("Generated all badges:"), .images(pictures), .text("Done.")
        ])
    }

    func testInlineImageKeepsSurroundingWordsAndShowsItsPreview() {
        let image = MessageImageAttachment(id: "one", name: "badge.png", markdown: "![Badge](badge.png)")
        XCTAssertEqual(MessageImageContent.parts("Inspect \(image.markdown) here.", images: [image]), [
            .text("Inspect \(image.markdown) here."), .images([image])
        ])
    }

    func testNoImagesPreservesMarkdownAndInvalidReferencesAreIgnored() {
        let text = "# Result\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        XCTAssertEqual(MessageImageContent.parts(text, images: []), [.text(text)])
        let invalid = MessageImageAttachment(id: "", name: "a.png", markdown: "[a](a.png)")
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(MessageImageContent.parts("[a](a.png)", images: [invalid]), [.text("[a](a.png)")])
    }
}
