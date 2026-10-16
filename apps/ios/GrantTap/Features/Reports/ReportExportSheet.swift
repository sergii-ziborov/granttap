import SwiftUI
import UIKit

/// Choose the shape, look at what goes out, hand it on.
///
/// The report leaves through the system share sheet and nothing else: the app
/// has no channel of its own, and a report that quietly uploaded itself would
/// contradict what GrantTap says about where its data goes.
struct ReportExportSheet: View {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case pdf, csv
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    // Live catalog updates must not change a document already being inspected.
    @State private var report: ProjectReport
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var format: Format
    @StateObject private var preview = ReportPreviewPreparation()
    @State private var shareURL: URL?

    init(report: ProjectReport, initialFormat: Format = .pdf, onClose: (() -> Void)? = nil) {
        _report = State(initialValue: report)
        self.onClose = onClose
        _format = State(initialValue: initialFormat)
    }

    private var file: ReportPreviewFile? {
        preview.file?.format == format ? preview.file : nil
    }

    var body: some View {
        ChatSheetNavigation(title: L("Report"), doneIdentifier: "report.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            VStack(spacing: 0) {
                context
                Picker(L("Format"), selection: $format) {
                    ForEach(Format.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("report.format")
                .padding(.horizontal, 20).padding(.bottom, 12)
                document
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                    .padding(.horizontal, 20)
                export
            }
            .background(Theme.bg)
            .task(id: format) { await preview.prepare(report, format: format) }
            .sheet(item: $shareURL) { url in ReportShareSheet(items: [url]) }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 640, idealWidth: 820, minHeight: 580, idealHeight: 780)
        #endif
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(report.title).font(.headline).foregroundStyle(Theme.ink)
                .lineLimit(2).textSelection(.enabled)
            Text(report.subtitle).font(.subheadline).lineLimit(1).truncationMode(.middle)
            Text(report.periodLine).font(.caption).lineLimit(2)
        }
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).padding(.bottom, -4)
    }

    @ViewBuilder private var document: some View {
        if let file {
            ReportDocumentPreview(file: file)
        } else if preview.failed {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.ellipsis").font(.title).foregroundStyle(Theme.muted)
                Text(L("Could not prepare report.")).foregroundStyle(Theme.ink)
                Button(L("Retry")) {
                    Task { await preview.prepare(report, format: format) }
                }
                .pointerButtonStyle().accessibilityIdentifier("report.retry")
            }
        } else {
            ProgressView(L("Preparing report…"))
                .accessibilityIdentifier("report.preparing")
        }
    }

    private var export: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L("Preview")).fontWeight(.semibold)
                Spacer()
                if let file { Text(file.details).accessibilityIdentifier("report.file.details") }
            }
            .font(.caption).foregroundStyle(Theme.muted)
            Button { shareURL = file?.url } label: {
                Label(L("Share report"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(FilledButton(tint: Theme.actionFill))
            .disabled(file == nil)
            .accessibilityIdentifier("report.share")
        }
        .padding(20).padding(.top, -4)
    }
}

// A file to share is presented by its own URL; the conformance is this app's,
// stated as such so a later one in Foundation is not silently shadowed.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

enum ReportFiles {
    /// Written to the temporary folder, where the system clears it later.
    static func write(_ report: ProjectReport, format: ReportExportSheet.Format,
                      directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let url = directory.appendingPathComponent("\(report.fileStem).\(format.rawValue)")
        let data = format == .pdf ? ReportPDF.render(report) : ReportCSV.data(report)
        try data.write(to: url, options: .atomic)
        return url
    }
}
