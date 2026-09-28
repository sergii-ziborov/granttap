import SwiftUI

enum ChatFileChanges {
    static func endingAt(_ finalId: String, entries: [ActivityEntry]) -> [RecordedFileChange] {
        guard let end = entries.firstIndex(where: { $0.id == finalId }) else { return [] }
        if let reported = entries[end].fileChanges { return reported }
        let start = entries[..<end].lastIndex(where: { $0.kind == "user" }) ?? 0
        let edits = entries[start...end].flatMap { $0.fileChanges ?? [] }
        return Dictionary(grouping: edits, by: \.path).map { path, edits in
            RecordedFileChange(path: path,
                linesAdded: edits.reduce(0) { $0 + $1.linesAdded },
                linesRemoved: edits.reduce(0) { $0 + $1.linesRemoved },
                diff: edits.map(\.diff).joined(separator: "\n"),
                diffTruncated: edits.contains { $0.diffTruncated == true } ? true : nil)
        }.sorted { $0.path < $1.path }
    }
}

struct ChatFileChangesCard: View {
    let files: [RecordedFileChange]
    var complete: Bool = true
    @State private var expanded: Bool
    @State private var selected: RecordedFileChange?

    init(files: [RecordedFileChange], complete: Bool = true, expanded: Bool = false) {
        self.files = files
        self.complete = complete
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(String(format: L("Edited %d files"), files.count), systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("chat.changes.summary")
                Spacer()
                Button(L("Review changes")) { expanded.toggle() }
                    .accessibilityIdentifier("chat.changes.review")
            }
            .padding(12)
            ForEach(expanded ? files : Array(files.prefix(3))) { file in
                Button { selected = file } label: {
                    HStack(spacing: 10) {
                        Text(file.path).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        DiffStatsBadge(added: file.linesAdded, removed: file.linesRemoved)
                        Image(systemName: "chevron.right")
                    }
                    .font(Theme.mono(12))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.changes.file.\(file.path)")
            }
            if files.count > 3 {
                Button(expanded ? L("Show fewer files")
                       : String(format: L("Show %d more files"), files.count - 3)) { expanded.toggle() }
                    .font(.system(size: 12)).padding(12)
            }
            Text(L("Recorded successful edits in this reply."))
                .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(12)
            if !complete {
                Text(L("The recorded changes exceed the history limit. This list is partial."))
                    .font(.caption).foregroundStyle(Theme.muted).padding(12)
            }
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .sheet(item: $selected) { file in
            ChatFileReviewSheet(file: file) { selected = nil }
        }
    }
}
