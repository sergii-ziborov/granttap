import Foundation

/// The report as a spreadsheet reads it: one block per table, figures first.
enum ReportCSV {
    static func render(_ report: ProjectReport) -> String {
        var lines: [String] = []
        lines.append(row([report.title, report.subtitle]))
        lines.append(row([L("Generated"), ReportBuilder.stamp(report.generatedAt.timeIntervalSince1970 * 1_000)]))
        lines.append(row([L("Period"), report.periodLine]))
        lines.append("")
        lines.append(row([L("Figure"), L("Value"), L("Note")]))
        for figure in report.figures {
            lines.append(row([figure.label, figure.value, figure.note ?? ""]))
        }
        for table in report.tables {
            lines.append("")
            lines.append(row([table.title]))
            lines.append(row(table.columns))
            for cells in table.rows { lines.append(row(cells)) }
            if let footnote = table.footnote { lines.append(row([footnote])) }
        }
        if !report.notes.isEmpty {
            lines.append("")
            for note in report.notes { lines.append(row([note])) }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Commas, quotes and line breaks stay inside their cell.
    static func row(_ cells: [String]) -> String {
        cells.map { cell -> String in
            let needsQuotes = cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r")
            let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
            return needsQuotes ? "\"\(escaped)\"" : escaped
        }.joined(separator: ",")
    }

    static func data(_ report: ProjectReport) -> Data {
        // A byte-order mark, so a spreadsheet opening the file reads UTF-8.
        Data([0xEF, 0xBB, 0xBF]) + Data(render(report).utf8)
    }
}
