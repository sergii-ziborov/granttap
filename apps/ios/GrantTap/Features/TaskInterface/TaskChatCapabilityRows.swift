import SwiftUI

/// What this chat can reach and what it has cost.
///
/// Assembling the rows is a different job from drawing the chat, and it is
/// the part that answers "which capability spent this context" — for the
/// task controls and for the Project policy shown beside them.
extension TaskChatView {

    /// Shell usage for the controls menu (computed on open — not sheet-present path).
    var chatShellRows: [(name: String, calls: Int, tokens: Int,
                                 commandPreview: String?)] {
        var shellMap: [String: (calls: Int, tokens: Int, commandPreview: String?,
                               lastUsedAt: Double)] = [:]
        for event in model.capabilityUsageEvents(forSessionId: chatSessionId)
        where event.kind == .cli {
            let prev = shellMap[event.name]
            shellMap[event.name] = (
                (prev?.calls ?? 0) + 1,
                (prev?.tokens ?? 0) + (event.estimatedContextTokens ?? 0),
                event.createdAt >= (prev?.lastUsedAt ?? 0)
                    ? event.commandPreview : prev?.commandPreview,
                max(event.createdAt, prev?.lastUsedAt ?? 0)
            )
        }
        return shellMap
            .map { (name: $0.key, calls: $0.value.calls, tokens: $0.value.tokens,
                    commandPreview: $0.value.commandPreview) }
            .sorted { $0.calls > $1.calls }
    }

    func capabilityUsageSummary(_ kind: CapabilityUsageKind,
                                        name: String) -> String? {
        let rows = model.capabilityUsageEvents(forSessionId: chatSessionId)
            .filter { $0.kind == kind && $0.name == name }
        guard !rows.isEmpty else { return nil }
        let tokens = rows.reduce(0) { $0 + ($1.estimatedContextTokens ?? 0) }
        return tokens > 0
            ? "\(rows.count)× · ≈ \(Format.tokens(tokens)) context"
            : "\(rows.count)×"
    }

    /// Every switchable capability of this chat, gathered from the three places
    /// the provider reports them, with what each has actually cost here.
    var capabilityRows: [ChatCapabilityRow] {
        let usage = model.capabilityUsageEvents(forSessionId: chatSessionId)
        func cost(_ kind: CapabilityUsageKind, _ name: String) -> (calls: Int, tokens: Int) {
            let rows = usage.filter { $0.kind == kind && $0.name == name }
            return (rows.count, rows.reduce(0) { $0 + ($1.estimatedContextTokens ?? 0) })
        }
        var out: [ChatCapabilityRow] = (currentSession.mcpServers ?? []).map { server in
            let spent = cost(.mcp, server.name)
            return ChatCapabilityRow(
                kind: .mcp, name: server.name,
                allowed: controlSupport.mcp ? server.allowed : nil,
                calls: spent.calls, tokens: spent.tokens,
                needsAuth: server.configuredEnabled == false
            )
        }
        out += (currentSession.skills ?? []).map { skill in
            let spent = cost(.skill, skill.name)
            return ChatCapabilityRow(
                kind: .skill, name: skill.name,
                allowed: controlSupport.skills ? skill.allowed != false : nil, calls: spent.calls,
                tokens: spent.tokens, needsAuth: false
            )
        }
        for row in chatShellRows {
            let spent = cost(.cli, row.name)
            out.append(ChatCapabilityRow(
                kind: .cli, name: row.name,
                allowed: controlSupport.cli ? currentSession.shellAllowed != false : nil,
                calls: spent.calls, tokens: spent.tokens, needsAuth: false
            ))
        }
        return out
    }
}
