import SwiftUI

struct ChatWorkFilesSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let files: [RecordedFileChange]
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var selected: RecordedFileChange?

    private enum Mode: String, CaseIterable {
        case modified = "Modified", allFiles = "All files"
    }

    init(model: AppModel, session: SessionInfo, files: [RecordedFileChange],
         onClose: (() -> Void)? = nil) {
        self.model = model
        self.session = session
        self.files = files
        self.onClose = onClose
        _mode = State(initialValue: files.isEmpty ? .allFiles : .modified)
    }

    var body: some View {
        ChatSheetNavigation(title: L("Files"), doneIdentifier: "chat.files.done",
            onClose: { if let onClose { onClose() } else { dismiss() } }) {
            VStack(spacing: 0) {
                Picker(L("Files view"), selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(L(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented).padding(16)
                .accessibilityIdentifier("chat.files.mode")
                if mode == .modified { modifiedFiles }
                else {
                    ZStack { ChatWorkspaceDirectoryView(model: model, session: session, path: "") }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat.files.workspace.viewport")
                }
            }
            .background(Theme.bg)
            .sheet(item: $selected) { file in
                ChatFileReviewSheet(file: file, model: model, session: session) { selected = nil }
            }
        }
    }

    private var modifiedFiles: some View {
        List {
            Section {
                HStack {
                    Text(LPlural(files.count, one: "%d file", many: "%d files"))
                    Spacer()
                    DiffStatsBadge(added: files.reduce(0) { $0 + $1.linesAdded },
                                   removed: files.reduce(0) { $0 + $1.linesRemoved })
                }
                Text(L("Recorded successful edits in this reply."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section(L("Modified")) {
                if files.isEmpty {
                    Text(L("No recorded edits in this reply.")).foregroundStyle(Theme.muted)
                }
                ForEach(files) { file in
                    Button { selected = file } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.muted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                Text(file.path).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                                    .lineLimit(2).truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            DiffStatsBadge(added: file.linesAdded, removed: file.linesRemoved)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink).padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("chat.files.modified.\(file.path)")
                }
            }
        }
    }
}
