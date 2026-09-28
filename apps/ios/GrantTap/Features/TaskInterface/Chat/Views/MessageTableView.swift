import SwiftUI

/// A markdown table as a grid: a header row, ruled rows, columns as wide as
/// their longest cell, the whole thing scrolling sideways when it must.
struct MessageTableView: View {
    let table: MessageMarkdown.Table

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !table.header.isEmpty {
                    row(table.header, bold: true)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, cells in
                    row(cells, bold: false)
                    if index < table.rows.count - 1 {
                        Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 0.5)
                    }
                }
            }
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityIdentifier("chat.table")
    }

    private func row(_ cells: [AttributedString], bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(table.columns, 1), id: \.self) { column in
                Text(table.cell(cells, column))
                    .font(.system(size: 12.5, weight: bold ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: Self.width(table, column: column), alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
    }

    /// Wide enough for the longest cell, within reason: a column of numbers
    /// stays narrow, a column of sentences wraps.
    static func width(_ table: MessageMarkdown.Table, column: Int) -> CGFloat {
        let longest = ([table.header] + table.rows)
            .compactMap { $0.count > column ? $0[column].characters.count : nil }
            .max() ?? 4
        return CGFloat(min(max(longest, 3), 28)) * 7.4 + 8
    }
}

/// Fenced code as a card: monospaced, on its own ground, scrolling sideways
/// rather than wrapping a line that was meant to stay one line.
struct MessageCodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityIdentifier("chat.code")
    }
}
