import Foundation

extension SessionInfo {
    /// Change the local root identity and keep direct child links attached to
    /// that root. Deeper parent links already point at stable child ids.
    func remappingLocalSessionRoot(to newSessionId: String) -> SessionInfo {
        var remapped = replacingLocalSessionValues(
            sessionId: newSessionId,
            title: title,
            cwd: cwd,
            state: state,
            lastActivityAt: lastActivityAt
        )
        remapped.childThreads = childThreads?.map { thread in
            guard thread.parentThreadId == sessionId else { return thread }
            return ChildThreadInfo(
                threadId: thread.threadId,
                parentThreadId: newSessionId,
                title: thread.title,
                agentName: thread.agentName,
                model: thread.model,
                depth: thread.depth,
                state: thread.state,
                startedAt: thread.startedAt,
                lastActivityAt: thread.lastActivityAt,
                tokensSession: thread.tokensSession,
                tokensLastTurn: thread.tokensLastTurn,
                contextTokensUsed: thread.contextTokensUsed,
                contextWindow: thread.contextWindow
            )
        }
        return remapped
    }

    /// Rebuild the immutable parts of a local row while retaining every field
    /// that the local send/remap flow does not intentionally change.
    func replacingLocalSessionValues(
        sessionId: String,
        title: String?,
        cwd: String?,
        state: String,
        lastActivityAt: Double
    ) -> SessionInfo {
        SessionInfo(
            sessionId: sessionId,
            agent: agent,
            title: title,
            cwd: cwd,
            branch: branch,
            model: model,
            summary: summary,
            accessLevel: accessLevel,
            state: state,
            startedAt: startedAt,
            lastActivityAt: lastActivityAt,
            tokensSession: tokensSession,
            tokensLastTurn: tokensLastTurn,
            contextTokensUsed: contextTokensUsed,
            contextWindow: contextWindow,
            mcpServers: mcpServers,
            skills: skills,
            childThreads: childThreads,
            shellAllowed: shellAllowed
        )
    }
}

@MainActor
extension AppModel {
    /// Demo fixture ids from AppModelDemo — never treat as live Mac chats.
    static func isGrantTapDemoSessionId(_ sessionId: String) -> Bool {
        let id = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        return id.hasPrefix("granttap-") && id.hasSuffix("-demo")
    }

    static func looksLikeSessionId(_ value: String?) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return false }
        let uuid = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return raw.range(of: uuid, options: .regularExpression) != nil
    }

    /// Failed decrypt / wrong-room blobs / id leakage must not appear as chat titles.
    static func looksLikeOpaqueCipherTitle(_ title: String?) -> Bool {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        if looksLikeSessionId(raw) { return true }
        let hexOnly = #"^[0-9a-fA-F]{28,}$"#
        if raw.range(of: hexOnly, options: .regularExpression) != nil { return true }
        guard raw.count >= 20 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/=_-"))
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let letters = raw.filter(\.isLetter)
        if letters.count < 16 { return raw.count >= 28 }
        let lower = letters.filter(\.isLowercase).count
        let upper = letters.filter(\.isUppercase).count
        let vowels = letters.filter { "aeiouAEIOU".contains($0) }.count
        let ratio = Double(vowels) / Double(letters.count)
        if ratio < 0.12 { return true }
        return lower > 0 && upper > 0 && ratio < 0.22
    }

    /// Reject an opaque value only when it was actually published as the title.
    /// A provider-native UUID with no title is still a valid, routable chat; Codex
    /// can legitimately omit its title while Mesh retains the Task's display name.
    static func isCodeBlobCatalogTitle(sessionId: String, title: String?) -> Bool {
        let id = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return false }
        if !id.isEmpty, t.caseInsensitiveCompare(id) == .orderedSame { return true }
        if !id.isEmpty, t.count >= 8, id.lowercased().hasPrefix(t.lowercased()) { return true }
        return looksLikeOpaqueCipherTitle(t)
    }

    static func filterRealCatalogSessions(_ rows: [SessionInfo], allowDemo: Bool) -> [SessionInfo] {
        guard !allowDemo else { return rows }
        return rows.filter {
            !isGrantTapDemoSessionId($0.sessionId)
                && !isCodeBlobCatalogTitle(sessionId: $0.sessionId, title: $0.title)
        }
    }

    /// Pairing / Exit Demo — wipe demo fixtures so they cannot linger in Active.

}
