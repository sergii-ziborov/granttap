import Foundation

/// One switchable capability of a chat, whatever kind it is.
///
/// MCP servers, skills and the shell used to live in three separate menu
/// sections with three different shapes, so the same question — "what can this
/// chat reach, how much has it cost, and can I turn it off?" — had three
/// different answers depending on where you looked.
struct ChatCapabilityRow: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case mcp, skill, cli

        var title: String {
            switch self {
            case .mcp: return L("MCP servers")
            case .skill: return L("Skills")
            case .cli: return L("Shell / CLI")
            }
        }

        var systemImage: String {
            switch self {
            case .mcp: return "shippingbox"
            case .skill: return "wand.and.stars"
            case .cli: return "terminal"
            }
        }
    }

    let kind: Kind
    let name: String
    /// Nil when the provider cannot enforce this, so the UI shows it read-only
    /// rather than pretending a switch did something.
    let allowed: Bool?
    let calls: Int
    let tokens: Int
    /// Listed by the provider but unusable until the user signs in.
    let needsAuth: Bool

    var id: String { "\(kind.rawValue):\(name)" }

    var isControllable: Bool { allowed != nil }

    var controlLabel: String? {
        allowed.map { $0 ? L("On") : L("Off") }
    }

    /// What this capability has actually cost, or nil when it has not run here.
    var usage: String? {
        guard calls > 0 else { return nil }
        return tokens > 0
            ? String(format: L("%d× · ≈ %@ ctx"), calls, Format.tokens(tokens))
            : String(format: L("%d×"), calls)
    }
}

enum ChatCapabilitySort {
    /// Heaviest first, then anything used at all, then the rest alphabetically.
    ///
    /// A list ordered purely by name buries the one server that is actually
    /// costing the chat, which is the row the user came to find.
    static func rank(_ rows: [ChatCapabilityRow]) -> [ChatCapabilityRow] {
        rows.sorted { left, right in
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            if left.calls != right.calls { return left.calls > right.calls }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    /// Share of the chat's measured capability tokens, or nil when nothing has
    /// been measured — a zero denominator must not render as a confident 0%.
    static func share(of row: ChatCapabilityRow, in rows: [ChatCapabilityRow]) -> Double? {
        let total = rows.reduce(0) { $0 + $1.tokens }
        guard total > 0, row.tokens > 0 else { return nil }
        return Double(row.tokens) / Double(total)
    }
}
