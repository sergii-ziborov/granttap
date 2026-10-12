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
        if let session, let live = presentable(session.title ?? "") { return live }
        return presentable(task.title) ?? L("Untitled Task")
    }

    /// The opening line of a published title, when that line reads as a name.
    static func presentable(_ raw: String) -> String? {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var trimmed = line.replacingOccurrences(
            of: #"^\[@[^]]+\]\(plugin://[^)]+\)\s*"#, with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("<external_codex_apps_open_page") else { return nil }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           Set(object.keys) == ["page_id"] { return nil }
        // Titles are labels, so the list and chat header show the same words
        // without rendering host mention URLs or Markdown punctuation.
        for (pattern, replacement) in [
            (#"^#{1,6}\s+"#, ""),
            (#"\[([^\]]+)\]\([^\)]+\)"#, "$1"),
            (#"(\*\*|__)(.*?)\1"#, "$2"),
            (#"(?<!\w)(\*|_)([^*_\n]+)\1(?!\w)"#, "$2"),
            (#"`([^`]+)`"#, "$1"),
        ] {
            trimmed = trimmed.replacingOccurrences(of: pattern, with: replacement,
                                                  options: .regularExpression)
        }
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


@MainActor
extension AppModel {
    /// Recover a missing native title from a real received message and retain it offline.
    func adoptTranscriptTitle(_ activity: SessionActivity) {
        guard let index = sessions.firstIndex(where: { $0.sessionId == activity.sessionId }),
              ProjectMeshTaskTitle.presentable(sessions[index].title ?? "") == nil,
              let title = activity.entries.filter({ $0.kind == "user" && $0.childThreadId == nil })
                .compactMap({ ProjectMeshTaskTitle.presentable($0.text) }).first else { return }
        var rows = sessions
        rows[index].title = title
        sessions = rows
        if !demoMode {
            SessionCatalogCache.save(.init(sessions: rows, history: sessionHistory,
                machine: machineName, tokensRecent: tokensRecent, tokenWindowHours: tokenWindowHours,
                generatedAt: lastSessionsGeneratedAt))
        }
    }
}
