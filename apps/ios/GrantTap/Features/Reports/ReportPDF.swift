import UIKit

/// The report as a person reads it: a title, the figures at a glance, then
/// each table, across as many A4 pages as it takes.
enum ReportPDF {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 40

    static func render(_ report: ProjectReport) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: report.title,
                kCGPDFContextCreator as String: "GrantTap",
            ]
            return format
        }())
        return renderer.pdfData { context in
            var page = Page(context: context, report: report)
            page.begin()
            page.header()
            page.figures()
            for table in report.tables { page.table(table) }
            page.notes()
        }
    }

    /// Where the pen is on the current page, and the moves it knows.
    struct Page {
        let context: UIGraphicsPDFRendererContext
        let report: ProjectReport
        var y: CGFloat = margin
        var number = 0
        var width: CGFloat { pageSize.width - margin * 2 }
        var bottom: CGFloat { pageSize.height - margin - 18 }

        static let ink = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        static let muted = UIColor(red: 0.45, green: 0.44, blue: 0.42, alpha: 1)
        static let line = UIColor(red: 0.85, green: 0.83, blue: 0.80, alpha: 1)
        static let band = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1)
        static let accent = UIColor(red: 0.75, green: 0.29, blue: 0.12, alpha: 1)

        mutating func begin() {
            context.beginPage()
            number += 1
            y = margin
            let footer = String(format: L("Page %d · GrantTap"), number)
            draw(footer, font: .systemFont(ofSize: 8), color: Self.muted,
                 rect: CGRect(x: margin, y: pageSize.height - margin, width: width, height: 12), alignment: .right)
        }

        /// Room for the next block, or a new page.
        mutating func ensure(_ height: CGFloat) {
            if y + height > bottom { begin() }
        }

        mutating func header() {
            draw(report.title, font: .boldSystemFont(ofSize: 22), color: Self.ink,
                 rect: CGRect(x: margin, y: y, width: width, height: 30))
            y += 30
            draw(report.subtitle, font: .systemFont(ofSize: 11), color: Self.muted,
                 rect: CGRect(x: margin, y: y, width: width, height: 16))
            y += 18
            let stamp = "\(L("Period")): \(report.periodLine)   ·   \(L("Generated")): \(ReportBuilder.stamp(report.generatedAt.timeIntervalSince1970 * 1_000))"
            draw(stamp, font: .systemFont(ofSize: 9), color: Self.muted,
                 rect: CGRect(x: margin, y: y, width: width, height: 14))
            y += 20
            rule()
        }

        mutating func figures() {
            let columns = 3
            let gap: CGFloat = 10
            let cardWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cardHeight: CGFloat = 58
            for (index, figure) in report.figures.enumerated() {
                let column = index % columns
                if column == 0 { ensure(cardHeight + gap) }
                let x = margin + CGFloat(column) * (cardWidth + gap)
                let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
                Self.band.setFill()
                path.fill()
                draw(figure.value, font: .boldSystemFont(ofSize: 18), color: Self.ink,
                     rect: rect.insetBy(dx: 10, dy: 0).offsetBy(dx: 0, dy: 8).with(height: 24))
                draw(figure.label.uppercased(), font: .systemFont(ofSize: 8, weight: .semibold), color: Self.muted,
                     rect: rect.insetBy(dx: 10, dy: 0).offsetBy(dx: 0, dy: 32).with(height: 11))
                if let note = figure.note {
                    draw(note, font: .systemFont(ofSize: 7.5), color: Self.muted,
                         rect: rect.insetBy(dx: 10, dy: 0).offsetBy(dx: 0, dy: 43).with(height: 11))
                }
                if column == columns - 1 || index == report.figures.count - 1 { y += cardHeight + gap }
            }
            y += 6
        }

        mutating func table(_ table: ProjectReport.Table) {
            let rowHeight: CGFloat = 16
            ensure(rowHeight * 3 + 24)
            draw(table.title, font: .boldSystemFont(ofSize: 13), color: Self.ink,
                 rect: CGRect(x: margin, y: y, width: width, height: 18))
            y += 22
            let widths = columnWidths(table)
            headerRow(table.columns, widths: widths, height: rowHeight)
            for (index, cells) in table.rows.enumerated() {
                if y + rowHeight > bottom {
                    begin()
                    headerRow(table.columns, widths: widths, height: rowHeight)
                }
                if index % 2 == 1 {
                    Self.band.withAlphaComponent(0.6).setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: y, width: width, height: rowHeight)).fill()
                }
                var x = margin
                for (column, cell) in cells.enumerated() where column < widths.count {
                    draw(cell, font: .systemFont(ofSize: 8.5), color: Self.ink,
                         rect: CGRect(x: x + 4, y: y + 2, width: widths[column] - 8, height: rowHeight - 4))
                    x += widths[column]
                }
                y += rowHeight
            }
            if let footnote = table.footnote {
                y += 4
                draw(footnote, font: .italicSystemFont(ofSize: 8), color: Self.muted,
                     rect: CGRect(x: margin, y: y, width: width, height: 12))
                y += 12
            }
            y += 14
        }

        mutating func notes() {
            for note in report.notes {
                let height = Self.height(of: note, font: .systemFont(ofSize: 8.5), width: width)
                ensure(height + 4)
                draw(note, font: .systemFont(ofSize: 8.5), color: Self.muted,
                     rect: CGRect(x: margin, y: y, width: width, height: height), wraps: true)
                y += height + 4
            }
        }

        private mutating func headerRow(_ columns: [String], widths: [CGFloat], height: CGFloat) {
            Self.band.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: width, height: height)).fill()
            var x = margin
            for (index, column) in columns.enumerated() {
                draw(column, font: .systemFont(ofSize: 8, weight: .semibold), color: Self.muted,
                     rect: CGRect(x: x + 4, y: y + 2, width: widths[index] - 8, height: height - 4))
                x += widths[index]
            }
            y += height
            rule()
        }

        /// The first column reads longest; numbers need less.
        private func columnWidths(_ table: ProjectReport.Table) -> [CGFloat] {
            let count = max(1, table.columns.count)
            let weights: [CGFloat] = (0..<count).map { index in
                let longest = ([table.columns[index]] + table.rows.compactMap { $0.count > index ? $0[index] : nil })
                    .map(\.count).max() ?? 4
                return CGFloat(min(max(longest, 4), 28))
            }
            let total = weights.reduce(0, +)
            return weights.map { $0 / total * width }
        }

        private mutating func rule() {
            Self.line.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: margin + width, y: y))
            path.lineWidth = 0.5
            path.stroke()
            y += 4
        }

        private func draw(
            _ text: String, font: UIFont, color: UIColor, rect: CGRect,
            alignment: NSTextAlignment = .left, wraps: Bool = false
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ])
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }

        static func height(of text: String, font: UIFont, width: CGFloat) -> CGFloat {
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil
            )
            return ceil(bounds.height) + 2
        }
    }
}

private extension CGRect {
    func with(height: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
