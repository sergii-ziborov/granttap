import Foundation

/// What to call a Task whose chat is not open on this phone.
///
/// A Task title is published by whichever computer saw the chat first, and that
/// machine often has only the agent's own summary to name it with — which is
/// the opening message, verbatim. The list of live chats never shows that,
/// because a live session is named by `displayTitle`; the Project and
/// Governance lists fell back to the published field and so gave the same chat
/// a different, unrecognisable name.
enum ProjectMeshTaskTitle {
    /// Longer than a name, shorter than a paragraph.
    static let maxLength = 72

    static func text(_ task: ProjectMeshTask, session: SessionInfo?) -> String {
        // Every source is bounded, including the live one. An agent names a chat
        // with the whole opening message, and the list of live chats only looks
        // right because it clips to a single line — the Project list has no such
        // limit, so an unbounded live title filled the row with five lines of
        // someone's prose.
        if let session, let live = presentable(session.displayTitle) { return live }
        return presentable(task.title) ?? L("Untitled chat")
    }

    /// The opening line of a published title, when that line reads as a name.
    static func presentable(_ raw: String) -> String? {
        let cleaned = ChatTranscriptText.display(raw)
        let line = cleaned.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A path or an identifier is residue rather than a name anyone chose,
        // and the same shapes `displayTitle` refuses are refused here.
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~/") else { return nil }
        let uuid = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        guard trimmed.range(of: uuid, options: .regularExpression) == nil else { return nil }
        guard trimmed.count > maxLength else { return trimmed }
        // A dump still says something about the Task; it just must not run past
        // the row, and it is cut on a word so the fragment stays readable.
        let cut = trimmed.prefix(maxLength)
        let head = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        return "\(head.trimmingCharacters(in: .whitespaces))…"
    }
}
