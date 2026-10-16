import Foundation
import CoreGraphics
import Combine

/// One immutable export. Both the native preview and Share use these bytes.
struct ReportPreviewFile {
    let url: URL
    let format: ReportExportSheet.Format
    let data: Data
    let pageCount: Int

    var csvText: String? {
        guard format == .csv else { return nil }
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        return String(data: Data(bytes), encoding: .utf8)
    }

    var details: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        return pageCount > 0
            ? "\(LPlural(pageCount, one: "%d page", many: "%d pages")) · \(size)" : size
    }

    static func prepare(_ report: ProjectReport, format: ReportExportSheet.Format,
                        directory: URL) throws -> Self {
        let folder = directory.appendingPathComponent("granttap-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let url = try ReportFiles.write(report, format: format, directory: folder)
            let data = try Data(contentsOf: url)
            let pages = format == .pdf
                ? CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init)?.numberOfPages ?? 0 : 0
            return Self(url: url, format: format, data: data, pageCount: pages)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

@MainActor
final class ReportPreviewPreparation: ObservableObject {
    @Published private(set) var file: ReportPreviewFile?
    @Published private(set) var failed = false
    private var prepared: [ReportExportSheet.Format: ReportPreviewFile] = [:]
    private var report: ProjectReport?
    private var request = UUID()
    private let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory) {
        self.directory = directory
    }

    /// Rendering stays off the UI thread; changing formats reuses prepared files.
    func prepare(_ report: ProjectReport, format: ReportExportSheet.Format) async {
        let request = UUID()
        self.request = request
        if self.report != report { prepared.removeAll(); self.report = report }
        failed = false
        file = prepared[format]
        if file != nil { return }
        let directory = directory
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ReportPreviewFile.prepare(report, format: format, directory: directory)
            }.value
            guard !Task.isCancelled, self.request == request else { return }
            prepared[format] = result
            file = result
        } catch {
            guard !Task.isCancelled, self.request == request else { return }
            failed = true
        }
    }
}
