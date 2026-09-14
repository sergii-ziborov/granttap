import SwiftUI
import UIKit

/// Hand the finished report to the system sheet, so the person chooses where it
/// goes. The app opens no channel of its own: it has none, and adding one to
/// carry user text off the device would contradict what it claims about itself.
struct ReportShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Describe what went wrong, attach what shows it, and send it yourself.
///
/// GrantTap ships no analytics and collects nothing, so a report that quietly
/// uploaded state would make that untrue. It is assembled here, shown in full,
/// and sent by the person.
struct BugReportView: View {
    @ObservedObject var model: AppModel
    @State private var description: String
    @State private var includeDiagnostics: Bool
    @State private var screenshot: UIImage?
    @State private var showPicker = false
    @State private var showShare = false

    /// Initial state is injectable for the same reason the task controls sheet
    /// takes it: a screen whose branches are all behind private state has
    /// branches nothing can check.
    init(
        model: AppModel,
        description: String = "",
        includeDiagnostics: Bool = true,
        screenshot: UIImage? = nil
    ) {
        self.model = model
        _description = State(initialValue: description)
        _includeDiagnostics = State(initialValue: includeDiagnostics)
        _screenshot = State(initialValue: screenshot)
    }

    private var report: DiagnosticsReport { model.diagnosticsReport() }

    /// Exactly what will be shared, so nothing travels unseen.
    var composed: String {
        var parts = [description.trimmingCharacters(in: .whitespacesAndNewlines)]
        if includeDiagnostics { parts.append(report.text) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n---\n")
    }

    var canSend: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shareItems: [Any] {
        screenshot.map { [composed, $0] as [Any] } ?? [composed]
    }

    var body: some View {
        List {
            Section {
                TextEditor(text: $description)
                    .frame(minHeight: 130)
                    .accessibilityIdentifier("bugreport.description")
            } header: {
                Text(L("What happened"))
            } footer: {
                Text(L("What you did, what you expected, and what happened instead."))
            }

            Section(L("Screenshot")) {
                Button {
                    showPicker = true
                } label: {
                    Label(
                        screenshot == nil ? L("Attach a screenshot") : L("Replace screenshot"),
                        systemImage: "photo"
                    )
                }
                if let screenshot {
                    Image(uiImage: screenshot)
                        .resizable().scaledToFit().frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button(L("Remove screenshot"), role: .destructive) { self.screenshot = nil }
                }
            }

            Section {
                Toggle(L("Include diagnostics"), isOn: $includeDiagnostics)
                if includeDiagnostics {
                    Text(report.text)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
            } footer: {
                Text(L("No keys, tokens, chat content or commands are included. Nothing is sent until you send it."))
            }

            Section {
                Button {
                    showShare = true
                } label: {
                    Label(L("Send report"), systemImage: "square.and.arrow.up")
                }
                .disabled(!canSend)
                .accessibilityIdentifier("bugreport.send")
            }
        }
        .navigationTitle(L("Report a problem"))
        .sheet(isPresented: $showPicker) {
            PhotoLibraryAttachmentPicker(maxSelectionCount: 1) { images in
                screenshot = images.first
                showPicker = false
            } onCancel: {
                showPicker = false
            }
        }
        .sheet(isPresented: $showShare) {
            ReportShareSheet(items: shareItems)
        }
    }
}
