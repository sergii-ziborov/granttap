import XCTest
@testable import GrantTap

final class MarkdownPasteTests: XCTestCase {
    func testMarkdownAndLargeTextBecomeLosslessPreviewableFiles() throws {
        for text in ["# Plan\n\n- First\n- Second\n", "- One item", "> Quoted text", "*Emphasis*", "---",
                     String(repeating: "Long text 🧑🏽‍💻\n", count: 1_000)] {
            let draft = try XCTUnwrap(MarkdownPaste.attachment(for: text))
            XCTAssertEqual(String(data: draft.data, encoding: .utf8), text)
            XCTAssertTrue(draft.name.hasSuffix(".md") || draft.name.hasSuffix(".txt"))
            XCTAssertEqual(try AttachmentPreviewFile(draft).text, text)
            try AttachmentDraft.validateTotal([draft])
        }
        XCTAssertNil(MarkdownPaste.attachment(for: "Please check this file."))
        XCTAssertNil(MarkdownPaste.attachment(for: "Use #123 as the issue number."))
    }

    func testAttachmentAdmissionKeepsExistingDraftsAndReportsCapacityWithoutTruncation() throws {
        var files: [AttachmentDraft] = []
        XCTAssertFalse(try MarkdownPaste.append("Ordinary text", to: &files))
        XCTAssertTrue(try MarkdownPaste.append("# First", to: &files))
        XCTAssertTrue(try MarkdownPaste.append("# Second", to: &files))
        XCTAssertEqual(files.map(\.name), ["Pasted.md", "Pasted-2.md"])
        for _ in files.count..<AttachmentDraft.maxCount {
            files.append(.init(name: UUID().uuidString, mimeType: "text/plain", data: Data([1])))
        }
        XCTAssertThrowsError(try MarkdownPaste.append("# Full", to: &files))
        XCTAssertEqual(files.count, AttachmentDraft.maxCount)
        XCTAssertThrowsError(try MarkdownPaste.append(String(repeating: "x", count: 6_000_001), to: &files))
        XCTAssertEqual(files.first?.data, Data("# First".utf8))
    }

}
