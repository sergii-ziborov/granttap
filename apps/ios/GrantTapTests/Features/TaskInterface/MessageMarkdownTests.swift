import XCTest
@testable import GrantTap

final class MessageMarkdownTests: XCTestCase {
    /// Full markdown kept the inline styles but ran every block into one line
    /// ("мониторе.Как это устроеноНа экране"); the breaks come back.
    func testParagraphsListsAndHeadingsKeepTheirBreaks() {
        let text = "# Как это устроено\n\nНа экране компьютера.\n\nВторой абзац.\n\n- один\n- два\n\n1. раз\n2. два"
        let rendered = String(MessageMarkdown.attributed(text).characters)
        XCTAssertTrue(rendered.contains("Как это устроено\n\nНа экране компьютера.\n\nВторой абзац."), rendered)
        XCTAssertTrue(rendered.contains("• один\n• два"), rendered)
        XCTAssertTrue(rendered.contains("1. раз\n2. два"), rendered)
        XCTAssertFalse(rendered.contains("#"), "the heading mark is styling, not text")
        XCTAssertEqual(String(MessageMarkdown.attributed("plain words").characters), "plain words")
        XCTAssertEqual(
            ChatTranscriptText.display("<timestamp>Saturday, Sep 19, 2026, 5:11 PM (UTC+3)</timestamp>\nThe graph is the towers."),
            "The graph is the towers."
        )
        XCTAssertEqual(
            ChatTranscriptText.display("<timestamp>Saturday, Sep 19, 2026, 5:11 PM (UTC+3)</timestamp>\n<user_query>pin this</user_query>"),
            "pin this"
        )
        XCTAssertEqual(String(MessageMarkdown.attributed("").characters), "")

        // Fenced code keeps its own block, and a heading is styling, not a mark.
        let code = String(MessageMarkdown.attributed("Run:\n\n```\nnpm test\n```\n\n## Then\n\nDone.").characters)
        XCTAssertTrue(code.contains("Run:\n\nnpm test"), code)
        XCTAssertTrue(code.contains("Then\n\nDone."), code)
        XCTAssertFalse(code.contains("```"))
        XCTAssertFalse(code.contains("##"))
        // A nested list item under a list item stays one line apart from its parent.
        let nested = String(MessageMarkdown.attributed("- parent\n  - child\n- sibling").characters)
        XCTAssertTrue(nested.contains("• parent\n• child\n• sibling") || nested.contains("parent\n"), nested)
    }
}

extension MessageMarkdownTests {
    @MainActor
    func testATableIsAGridAndCodeIsACard() {
        let text = "Доступно: 8 компаний\n\n| компания | ATS | вакансий |\n|---|---|---|\n| Ceragon | Comeet | 43 |\n| OX Security | Comeet | 13 |\n\nИтого."
        let blocks = MessageMarkdown.blocks(text)
        XCTAssertEqual(blocks.count, 3, "\(blocks)")
        guard case .table(let table) = blocks[1] else { return XCTFail("the middle block is the table") }
        XCTAssertEqual(table.header.map { String($0.characters) }, ["компания", "ATS", "вакансий"])
        XCTAssertEqual(table.rows.map { $0.map { String($0.characters) } }, [["Ceragon", "Comeet", "43"], ["OX Security", "Comeet", "13"]])
        XCTAssertEqual(table.columns, 3)
        XCTAssertEqual(String(table.cell(table.rows[0], 7).characters), "", "a missing cell is empty, never a crash")
        XCTAssertGreaterThan(MessageTableView.width(table, column: 0), MessageTableView.width(table, column: 2))
        if case .text(let head) = blocks[0] { XCTAssertEqual(String(head.characters), "Доступно: 8 компаний") } else { XCTFail() }
        if case .text(let tail) = blocks[2] { XCTAssertEqual(String(tail.characters), "Итого.") } else { XCTFail() }
        let flat = String(MessageMarkdown.attributed(text).characters)
        XCTAssertTrue(flat.contains("компания | ATS | вакансий\nCeragon | Comeet | 43"), flat)

        let code = MessageMarkdown.blocks("Run:\n\n```swift\nlet x = 1\nprint(x)\n```\n\nDone.")
        XCTAssertEqual(code.count, 3, "\(code)")
        if case .code(let body, let language) = code[1] {
            XCTAssertEqual(body, "let x = 1\nprint(x)")
            XCTAssertEqual(language, "swift")
        } else {
            XCTFail("the middle block is code")
        }
        XCTAssertEqual(MessageMarkdown.blocks("plain words").count, 1)
        XCTAssertEqual(MessageMarkdown.blocks("").count, 1)

        RenderProbe.render(RichMessageText(text: text, compact: false))
        RenderProbe.render(RichMessageText(text: text, compact: true))
        RenderProbe.render(RichMessageText(text: "Run:\n\n```\nnpm test\n```", compact: false))
        RenderProbe.render(MessageCodeBlock(code: "a\nb", language: nil))
    }
}
