import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Markdown as a chat bubble shows it.
///
/// Full markdown keeps the inline styles, but `Text` ignores the block
/// structure the parser found, so paragraphs, headings, and list items ran
/// into one line ("мониторе.Как это устроеноНа экране"). The breaks are put
/// back from the parser's own block intents: a new paragraph starts on its own
/// line, a list item on its own line with a bullet or its number, a heading in
/// bold. A table and a fenced code block are not text at all: each becomes a
/// block of its own, drawn as a grid or as a monospaced card, where one `Text`
/// had printed every cell on its own line.
enum MessageMarkdown {
    enum Block: Equatable {
        case text(AttributedString)
        case table(Table)
        case code(String, language: String?)
    }

    struct Table: Equatable {
        var header: [AttributedString] = []
        var rows: [[AttributedString]] = []
        /// The parser's row numbers, in the order the rows were met.
        var rowOrder: [Int] = []

        var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

        func cell(_ row: [AttributedString], _ column: Int) -> AttributedString {
            column < row.count ? row[column] : AttributedString()
        }
    }

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for block in blocks(text) {
            if !result.characters.isEmpty { result += AttributedString("\n\n") }
            switch block {
            case .text(let piece): result += piece
            case .code(let code, _): result += AttributedString(code)
            case .table(let table):
                let lines = ([table.header] + table.rows).filter { !$0.isEmpty }.map { row in
                    row.map { String($0.characters) }.joined(separator: " | ")
                }
                result += AttributedString(lines.joined(separator: "\n"))
            }
        }
        return result.characters.isEmpty ? AttributedString(text) : result
    }

    static func blocks(_ text: String) -> [Block] {
        guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)) else {
            return [.text(AttributedString(text))]
        }
        var blocks: [Block] = []
        var prose = ProseBuilder()
        var table: (identity: Int, table: Table)?
        var code: (identity: Int, language: String?, text: String)?

        func flushProse() {
            if let piece = prose.take() { blocks.append(.text(piece)) }
        }
        func flushTable() {
            if let table { blocks.append(.table(table.table)) }
            table = nil
        }
        func flushCode() {
            if let code {
                blocks.append(.code(code.text.trimmingCharacters(in: .newlines), language: code.language))
            }
            code = nil
        }

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            var piece = AttributedString(parsed[run.range])
            piece.presentationIntent = nil
            if let tableIntent = components.first(where: { if case .table = $0.kind { return true } else { return false } }) {
                flushProse()
                flushCode()
                if table?.identity != tableIntent.identity { flushTable(); table = (tableIntent.identity, Table()) }
                let header = components.contains { if case .tableHeaderRow = $0.kind { return true } else { return false } }
                let rowIndex = components.compactMap { component -> Int? in
                    if case .tableRow(let index) = component.kind { return index } else { return nil }
                }.first ?? 0
                let column = components.compactMap { component -> Int? in
                    if case .tableCell(let index) = component.kind { return index } else { return nil }
                }.first ?? 0
                table?.table.append(piece, header: header, row: rowIndex, column: column)
                continue
            }
            if let codeIntent = components.first(where: { if case .codeBlock = $0.kind { return true } else { return false } }) {
                flushProse()
                flushTable()
                var language: String?
                if case .codeBlock(let hint) = codeIntent.kind { language = hint }
                if code?.identity != codeIntent.identity { flushCode(); code = (codeIntent.identity, language, "") }
                code?.text += String(parsed[run.range].characters)
                continue
            }
            flushTable()
            flushCode()
            prose.append(piece, components: components)
        }
        flushProse()
        flushTable()
        flushCode()
        return blocks.isEmpty ? [.text(AttributedString(text))] : blocks
    }

    /// Runs of plain markdown joined back into one string with its breaks.
    private struct ProseBuilder {
        private var result = AttributedString()
        private var previous: [PresentationIntent.IntentType] = []

        mutating func append(_ piece: AttributedString, components: [PresentationIntent.IntentType]) {
            var piece = piece
            if components.map(\.identity) != previous.map(\.identity) {
                if !result.characters.isEmpty {
                    result += AttributedString(MessageMarkdown.shareBlock(components, previous) ? "\n" : "\n\n")
                }
                if let item = MessageMarkdown.listItem(components), item.identity != MessageMarkdown.listItem(previous)?.identity {
                    result += AttributedString(MessageMarkdown.marker(components))
                }
            }
            for component in components {
                if case .header = component.kind {
                    piece.inlinePresentationIntent = .stronglyEmphasized
                }
            }
            result += piece
            previous = components
        }

        mutating func take() -> AttributedString? {
            defer { result = AttributedString(); previous = [] }
            return result.characters.isEmpty ? nil : result
        }
    }

    fileprivate static func listItem(_ components: [PresentationIntent.IntentType]) -> PresentationIntent.IntentType? {
        components.first { if case .listItem = $0.kind { return true } else { return false } }
    }

    /// Consecutive items of one list, or paragraphs of one item, sit one line apart.
    fileprivate static func shareBlock(
        _ current: [PresentationIntent.IntentType], _ previous: [PresentationIntent.IntentType]
    ) -> Bool {
        let lists = Set(current.filter(isList).map(\.identity))
        let items = Set(current.compactMap { component -> Int? in
            if case .listItem = component.kind { return component.identity } else { return nil }
        })
        return previous.contains { component in
            (isList(component) && lists.contains(component.identity))
                || items.contains(component.identity) && listItem([component]) != nil
        }
    }

    private static func isList(_ component: PresentationIntent.IntentType) -> Bool {
        switch component.kind {
        case .orderedList, .unorderedList: return true
        default: return false
        }
    }

    fileprivate static func marker(_ components: [PresentationIntent.IntentType]) -> String {
        guard let item = listItem(components), case .listItem(let ordinal) = item.kind else { return "" }
        let ordered = components.contains { if case .orderedList = $0.kind { return true } else { return false } }
        return ordered ? "\(ordinal). " : "• "
    }
}

extension MessageMarkdown.Table {
    mutating func append(_ piece: AttributedString, header isHeader: Bool, row: Int, column: Int) {
        if isHeader {
            while header.count <= column { header.append(AttributedString()) }
            header[column] += piece
            return
        }
        // Body rows keep the order they first appear in, whatever the parser
        // numbered them; a row's cells land in their columns.
        let index: Int
        if let known = rowOrder.firstIndex(of: row) {
            index = known
        } else {
            rowOrder.append(row)
            rows.append([])
            index = rows.count - 1
        }
        while rows[index].count <= column { rows[index].append(AttributedString()) }
        rows[index][column] += piece
    }
}

/// Cursor host tags that leaked into the transcript. They are not the message.
enum ChatTranscriptText {
    static func display(_ text: String) -> String {
        var next = text.replacingOccurrences(
            of: "<timestamp\\b[^>]*>[\\s\\S]*?</timestamp>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if let query = queryBody(in: next) {
            next = query
        } else if let start = openQueryRange(in: next) {
            next = String(next[start.upperBound...])
        }
        next = next.replacingOccurrences(
            of: "</?user_query\\b[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        next = next.replacingOccurrences(
            of: "</?timestamp\\b[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return next.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func queryBody(in text: String) -> String? {
        guard let start = openQueryRange(in: text),
              let end = text.range(
                of: "</user_query\\b[^>]*>",
                options: [.regularExpression, .caseInsensitive]
              ),
              start.upperBound < end.lowerBound else { return nil }
        let body = text[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : String(body)
    }

    private static func openQueryRange(in text: String) -> Range<String.Index>? {
        text.range(
            of: "<user_query\\b[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

struct RichMessageText: View {
    let text: String
    let compact: Bool

    private var shown: String { ChatTranscriptText.display(text) }
    private var attributed: AttributedString { MessageMarkdown.attributed(shown) }

    var body: some View {
        if compact {
            plain
        } else {
            let blocks = MessageMarkdown.blocks(shown)
            if blocks.count == 1, case .text = blocks[0] {
                plain
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let piece):
                            Text(piece)
                                .font(.system(size: 16))
                                .lineSpacing(2.5)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        case .table(let table):
                            MessageTableView(table: table)
                        case .code(let code, let language):
                            MessageCodeBlock(code: code, language: language)
                        }
                    }
                }
            }
        }
    }

    private var plain: some View {
        Text(attributed)
            .font(.system(size: compact ? 12.5 : 16))
            .lineSpacing(compact ? 0 : 2.5)
            .foregroundStyle(Theme.ink)
            .lineLimit(compact ? 3 : nil)
            .fixedSize(horizontal: false, vertical: !compact)
            .textSelection(.enabled)
    }
}
