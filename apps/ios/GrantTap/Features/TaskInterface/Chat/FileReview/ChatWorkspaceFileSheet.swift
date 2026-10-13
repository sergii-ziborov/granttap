import SwiftUI

@MainActor
struct ChatWorkspaceFileSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [Int: TaskWorkspaceSnapshot]
    @State private var loading = false
    @State private var failed = false

    init(model: AppModel, session: SessionInfo, path: String) {
        self.model = model
        self.session = session
        self.path = path
        let cached = model.cachedTaskWorkspace(for: session, mode: "file", path: path)
        _pages = State(initialValue: cached.map { [0: $0] } ?? [:])
    }

    private var latest: TaskWorkspaceSnapshot? { pages[pages.keys.max() ?? 0] }
    private var text: String { pages.keys.sorted().compactMap { pages[$0]?.text }.joined() }

    var body: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(path).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    .textSelection(.enabled).padding(16)
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
            .navigationBarTitleDisplayMode(.inline)
            .pageNavigationTitle(URL(fileURLWithPath: path).lastPathComponent,
                                 showsBack: false, actionPlacement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
            .task(id: path) { await load(offset: 0) }
        }
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
