import SwiftUI
import UIKit

/// Choose the shape, look at what goes out, hand it on.
///
/// The report leaves through the system share sheet and nothing else: the app
/// has no channel of its own, and a report that quietly uploaded itself would
/// contradict what GrantTap says about where its data goes.
struct ReportExportSheet: View {
    enum Format: String, CaseIterable, Identifiable {
        case pdf, csv
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    let report: ProjectReport
    @Environment(\.dismiss) private var dismiss
    @State private var format: Format = .pdf
    @State private var shareURL: URL?
    @State private var error: String?

    init(report: ProjectReport, initialFormat: Format = .pdf) {
        self.report = report
        _format = State(initialValue: initialFormat)
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Picker(L("Format"), selection: $format) {
                        ForEach(Format.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(format == .pdf
                         ? L("A document to read and forward: figures first, then every table.")
                         : L("One file for a spreadsheet: the figures, then each table as a block."))
                }
                Section {
                    ForEach(report.figures) { figure in
                        HStack(alignment: .firstTextBaseline) {
                            Text(figure.label).foregroundStyle(Theme.ink)
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(figure.value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                if let note = figure.note {
                                    Text(note).font(.caption2).foregroundStyle(Theme.muted)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                } header: {
                    Text(report.title)
                } footer: {
                    Text("\(report.subtitle)\n\(L("Period")): \(report.periodLine)")
                }
                Section {
                    ForEach(report.tables) { table in
                        HStack {
                            Text(table.title)
                            Spacer()
                            Text(LPlural(table.rows.count, one: "%d row", many: "%d rows"))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } header: {
                    Text(L("Tables"))
                }
                Section {
                    Button {
                        share()
                    } label: {
                        Label(L("Share report"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("report.share")
                    if let error {
                        Text(error).font(.caption).foregroundStyle(Theme.riskHigh)
                    }
                } footer: {
                    Text(L("Nothing leaves this phone until you choose where it goes."))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Report"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $shareURL) { url in
                ReportShareSheet(items: [url])
            }
        }
    }

    /// The file the share sheet hands on; nil when it could not be written.
    @discardableResult
    func share() -> URL? {
        do {
            let url = try ReportFiles.write(report, format: format)
            error = nil
            shareURL = url
            return url
        } catch {
            self.error = error.localizedDescription
            return nil
        }
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
