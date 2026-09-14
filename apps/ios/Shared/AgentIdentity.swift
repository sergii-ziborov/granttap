import Foundation

enum AgentIdentity {
    static let knownIds = ["claude", "codex", "cursor", "grok"]
    static let composeIds = ["claude", "codex", "cursor", "grok"]
    /// Agents whose CLI accepts a model and permission mode for one headless
    /// turn. Listing an agent here without that support would offer a setting
    /// the computer silently ignores.
    static let answerCapableAgents = ["claude", "codex", "cursor", "grok"]

    static func normalize(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return "codex" }
        if knownIds.contains(value) { return value }
        if value.contains("claude") { return "claude" }
        if value.contains("codex") { return "codex" }
        if value.contains("cursor") { return "cursor" }
        if value.contains("grok") { return "grok" }
        return value
    }

    static func displayName(_ value: String) -> String {
        switch normalize(value) {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        case "grok": return "Grok Build"
        default: return rawTitle(value)
        }
    }

    static func shortName(_ value: String) -> String {
        switch normalize(value) {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        case "grok": return "Grok"
        default: return rawTitle(value)
        }
    }

    static func glyph(_ value: String) -> String {
        switch normalize(value) {
        case "claude": return "C"
        case "codex": return "▚"
        case "cursor": return "⟩"
        case "grok": return "G"
        default: return String(rawTitle(value).prefix(1)).uppercased()
        }
    }

    static func newTaskLabel() -> String { L("New task") }

    private static func rawTitle(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = value.first else { return "Agent" }
        return String(first).uppercased() + value.dropFirst()
    }
}
