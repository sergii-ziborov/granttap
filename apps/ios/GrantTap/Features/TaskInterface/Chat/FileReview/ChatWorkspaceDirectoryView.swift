import SwiftUI

@MainActor
struct ChatWorkspaceDirectoryView: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    let path: String
    @State private var entries: [TaskWorkspaceEntry]
    @State private var nextOffset: Int?
    @State private var snapshot: TaskWorkspaceSnapshot?
    @State private var loading = false
    @State private var failed = false
    @State private var expanded: Set<String> = []
    @State private var selected: TaskWorkspaceEntry?

    init(model: AppModel, session: SessionInfo, path: String) {
        self.model = model
        self.session = session
        self.path = path
        let cached = model.cachedTaskWorkspace(for: session, mode: "directory", path: path)
        _snapshot = State(initialValue: cached)
        _entries = State(initialValue: cached?.entries ?? [])
        _nextOffset = State(initialValue: cached?.nextOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if path.isEmpty {
                Text(L("This Task's workspace"))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(entries) { entry in
                if entry.kind == "directory" { directory(entry) }
                else {
                    Button { selected = entry } label: { entryLabel(entry) }
                        .pointerButtonStyle()
                        .accessibilityIdentifier("chat.files.workspace.\(entry.path)")
                }
            }
            if entries.isEmpty && (loading || snapshot == nil && !failed) {
                ProgressView(L("Loading workspace files…")).padding(.vertical, 12)
            } else if entries.isEmpty {
                Text(snapshot?.unavailable == true || failed
                     ? L("This folder is unavailable. Connect this Task's computer and retry.")
                     : L("No files in this folder."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            }
            if failed || snapshot?.unavailable == true {
                Button(L("Retry")) { Task { await load(offset: 0) } }
                    .disabled(loading)
            }
            if snapshot?.truncated == true {
                Text(L("This folder list is partial."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let nextOffset {
                Button {
                    Task { await load(offset: nextOffset) }
                } label: {
                    if loading { ProgressView() }
                    else { Label(L("Load more files"), systemImage: "ellipsis") }
                }
                .disabled(loading)
                .accessibilityIdentifier("chat.files.load-more.\(path)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .task(id: path) { await load(offset: 0) }
        .sheet(item: $selected) { entry in
            ChatWorkspaceFileSheet(model: model, session: session, path: entry.path)
        }
    }

    private func directory(_ entry: TaskWorkspaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if expanded.contains(entry.path) { expanded.remove(entry.path) }
                else { expanded.insert(entry.path) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded.contains(entry.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                    entryLabel(entry)
                }
            }
            .pointerButtonStyle()
            .accessibilityIdentifier("chat.files.workspace.\(entry.path)")
            if expanded.contains(entry.path) {
                AnyView(ChatWorkspaceDirectoryView(model: model, session: session, path: entry.path))
                    .padding(.leading, 18)
            }
        }
    }

    private func entryLabel(_ entry: TaskWorkspaceEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.kind == "directory" ? "folder" : "doc.text")
                .foregroundStyle(Theme.muted).frame(width: 20)
            Text(entry.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let size = entry.size, entry.kind == "file" {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 8).contentShape(Rectangle())
    }

    private func load(offset: Int) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await model.readTaskWorkspace(for: session, mode: "directory",
                                                         path: path, offset: offset)
            if result.unavailable != true {
                let previous = offset == 0 ? [] : entries
                var seen = Set(previous.map(\.path))
                entries = previous + (result.entries ?? []).filter { seen.insert($0.path).inserted }
                nextOffset = result.nextOffset
            }
            snapshot = result
            failed = false
        } catch is CancellationError {} catch { failed = true }
    }
}
