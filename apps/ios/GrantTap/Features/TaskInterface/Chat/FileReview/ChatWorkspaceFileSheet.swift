import SwiftUI

@MainActor
struct ChatWorkspaceFileSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let path: String
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [Int: TaskWorkspaceSnapshot]
    @State private var loading = false
    @State private var failed = false
    @ObservedObject var editSession: TaskFileEditSession
    private var editor: TaskFileEditDraft? {
        editSession.draft.flatMap { $0.snapshot.sessionId == session.sessionId ? $0 : nil }
    }

    init(model: AppModel, session: SessionInfo, path: String, editSession: TaskFileEditSession, onClose: (() -> Void)? = nil) {
        self.model = model
        self.session = session
        self.path = path
        self.editSession = editSession
        self.onClose = onClose
        let cached = model.cachedTaskWorkspace(for: session, mode: "file", path: path)
        _pages = State(initialValue: cached.map { [0: $0] } ?? [:])
    }

    private var latest: TaskWorkspaceSnapshot? { pages[pages.keys.max() ?? 0] }
    private var text: String { pages.keys.sorted().compactMap { pages[$0]?.text }.joined() }

    var body: some View {
        ChatSheetNavigation(title: editor == nil ? URL(fileURLWithPath: path).lastPathComponent : L("Edit file"),
            doneIdentifier: editor == nil ? "chat.files.preview.done" : "chat.file-edit.done",
            dismissesPresentation: editor == nil, onClose: closeAction) {
            if let editor { ChatFileEditView(model: model, session: session, buffer: editor) }
            else { preview }
        }
    }

    private var closeAction: () -> Void {
        let store = editSession, finish = onClose ?? { dismiss() }
        return {
            if let draft = store.draft { draft.requestClose { store.draft = nil } }
            else { finish() }
        }
    }

    private var editableSnapshot: TaskWorkspaceSnapshot? {
        guard pages.count == 1, let first = pages[0], first.text != nil,
              !first.truncated, first.nextOffset == nil, first.unavailable != true else { return nil }
        return first
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(path).font(Theme.mono(11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let snapshot = editableSnapshot {
                    Button { editSession.draft = TaskFileEditDraft(snapshot: snapshot) } label: { Label(L("Edit"), systemImage: "square.and.pencil") }
                        .accessibilityIdentifier("chat.files.preview.edit")
                }
            }.padding(16)
            if pages.values.contains(where: { $0.text != nil }) {
                ChatFileDiffViewport {
                    Text(text).font(Theme.mono(12)).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("chat.files.preview.text")
                }
            } else if loading || pages.isEmpty && !failed {
                ProgressView(L("Loading file preview…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                    Text(L("This file preview is unavailable."))
                    Button(L("Retry")) { Task { await load(offset: 0) } }
                }
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            previewStatus
        }
        .background(Theme.bg)
        .task(id: path) { await load(offset: 0) }
    }

    @ViewBuilder private var previewStatus: some View {
        if failed && !text.isEmpty {
            Text(L("The saved preview remains available. Refresh could not reach the computer."))
                .font(.caption).foregroundStyle(Theme.muted).padding(16)
        }
        if latest?.truncated == true {
            HStack {
                Text(L("Partial file preview")).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if let offset = latest?.nextOffset {
                    Button {
                        Task { await load(offset: offset) }
                    } label: {
                        if loading { ProgressView() } else { Text(L("Load more")) }
                    }
                    .disabled(loading).accessibilityIdentifier("chat.files.preview.more")
                }
            }
            .padding(16)
        }
        if !text.isEmpty && editableSnapshot == nil {
            Text(L("Editing requires a complete text preview up to 128 KB."))
                .font(.caption).foregroundStyle(Theme.muted).padding(16)
        }
    }

    private func load(offset: Int) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await model.readTaskWorkspace(for: session, mode: "file",
                                                         path: path, offset: offset)
            if result.text != nil {
                if offset == 0 { pages = [0: result] } else { pages[offset] = result }
            } else if pages.isEmpty { pages[offset] = result }
            failed = result.unavailable == true
        } catch is CancellationError {} catch { failed = true }
    }
}
