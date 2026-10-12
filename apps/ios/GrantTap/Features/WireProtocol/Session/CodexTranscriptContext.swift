import Foundation

/// Host metadata can arrive in live payloads or in an archive from an older runtime.
enum CodexTranscriptContext {
    private static let selectedPage = "(?is)^(?:\\s*<external_codex_apps_open_page\\b[^>]*>"
        + "[\\s\\S]*?(?:</external_codex_apps_open_page\\s*>|$))+"

    static func visibleEntry(_ entry: ActivityEntry, agent: String) -> ActivityEntry? {
        guard agent == "codex", entry.kind == "user",
              !entry.id.hasPrefix("local-user-") else { return entry }
        let contextFree = entry.text.replacingOccurrences(of: selectedPage, with: "",
                                                          options: .regularExpression)
        guard contextFree != entry.text else { return entry }
        var visible = entry
        visible.text = contextFree.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.text.isEmpty || visible.attachments?.isEmpty == false
                || visible.images?.isEmpty == false else { return nil }
        return visible
    }
}
