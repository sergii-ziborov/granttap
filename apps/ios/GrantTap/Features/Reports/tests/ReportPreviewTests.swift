import PDFKit
import XCTest
@testable import GrantTap

@MainActor
final class ReportPreviewTests: XCTestCase {
    private func report(title: String = "Preview report") -> ProjectReport {
        ProjectReport(title: title, subtitle: "Task report · Demo workspace", generatedAt: Date(),
            periodStart: nil, periodEnd: nil,
            figures: [.init(label: "Tokens", value: "1.2k")],
            tables: [.init(title: "Tools", columns: ["Name", "Calls"],
                           rows: [["tool, quoted \"one\"", "2"], ["last tool", "1"]])],
            notes: ["Only observed activity."])
    }

    func testPDFPreviewAndShareUseTheSameCompleteFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparation = ReportPreviewPreparation(directory: directory)
        await preparation.prepare(report(), format: .pdf)
        let file = try XCTUnwrap(preparation.file)
        XCTAssertEqual(file.data, try Data(contentsOf: file.url))
        XCTAssertNil(file.csvText)
        let document = try XCTUnwrap(PDFDocument(data: file.data))
        XCTAssertEqual(document.pageCount, file.pageCount)
        XCTAssertGreaterThan(file.pageCount, 0)
        XCTAssertTrue(file.details.contains("·"))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("last tool"))
        XCTAssertTrue(text.contains("Only observed activity."))
        RenderProbe.render(ReportDocumentPreview(file: file))
    }

    func testCSVPreviewPreservesExportedCellsAndFormatSwitchesReuseFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preparation = ReportPreviewPreparation(directory: directory)
        let report = report()
        await preparation.prepare(report, format: .csv)
        let csv = try XCTUnwrap(preparation.file)
        XCTAssertEqual(csv.data, try Data(contentsOf: csv.url))
        XCTAssertEqual(csv.csvText, ReportCSV.render(report))
        XCTAssertEqual(csv.pageCount, 0)
        XCTAssertFalse(csv.details.isEmpty)
        RenderProbe.render(ReportDocumentPreview(file: csv))
        await preparation.prepare(report, format: .pdf)
        XCTAssertEqual(preparation.file?.format, .pdf)
        await preparation.prepare(report, format: .csv)
        XCTAssertEqual(preparation.file?.url, csv.url)
        XCTAssertEqual(preparation.file?.data, csv.data)
        let changed = self.report(title: "Different task")
        await preparation.prepare(changed, format: .csv)
        XCTAssertNotEqual(preparation.file?.url, csv.url)
        XCTAssertEqual(preparation.file?.csvText, ReportCSV.render(changed))
    }

    func testPreparationFailureCanBeRetriedAfterStorageRecovers() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocked".utf8).write(to: directory)
        let preparation = ReportPreviewPreparation(directory: directory)
        await preparation.prepare(report(), format: .csv)
        XCTAssertTrue(preparation.failed)
        XCTAssertNil(preparation.file)
        try FileManager.default.removeItem(at: directory)
        await preparation.prepare(report(), format: .csv)
        XCTAssertFalse(preparation.failed)
        XCTAssertNotNil(preparation.file)
    }

    func testPDFWrapsLongTitlesWithoutLosingTheEnd() throws {
        let title = "A long report title that needs multiple lines to describe this task and its final title marker"
        let document = try XCTUnwrap(PDFDocument(data: ReportPDF.render(report(title: title))))
        let text = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertTrue(text.contains("final title marker"), text)
        XCTAssertTrue(text.contains("Task report"))
        XCTAssertTrue(text.contains("TOKENS"))
    }

    func testCSVNativeViewportScrollsLongRowsAndAllLines() {
        let view = ReportCSVScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let row = (0..<20).map { "column\($0)" }.joined(separator: ",")
        view.show(Array(repeating: row, count: 100).joined(separator: "\r\n"))
        view.layoutIfNeeded()
        XCTAssertGreaterThan(view.contentSize.width, 700)
        XCTAssertGreaterThan(view.contentSize.height, 1_000)
        XCTAssertGreaterThan(view.textView.textContainer.size.width, 700,
                             "A long CSV row stays wide instead of wrapping at the viewport edge.")
        view.setContentOffset(CGPoint(x: 200, y: 300), animated: false)
        XCTAssertEqual(view.contentOffset.x, 200)
        XCTAssertEqual(view.contentOffset.y, 300)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("report-preview-test-\(UUID().uuidString)")
    }
}
