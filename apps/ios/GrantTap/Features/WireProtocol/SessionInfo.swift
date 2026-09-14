import Foundation

struct SessionInfo: Codable, Identifiable, Equatable {
    let sessionId: String
    let agent: String
    var projectId: String? = nil
    var taskId: String? = nil
    var computerId: String? = nil
    var title: String?
    var cwd: String?
    var branch: String?
    var worktree: String? = nil
    var model: String?
    var summary: String? = nil
    var accessLevel: String? = nil
    var state: String          // "working" | "waiting" | "idle"
    let startedAt: Double
    var lastActivityAt: Double
    let tokensSession: Int
    let tokensLastTurn: Int
    var contextTokensUsed: Int? = nil
    var contextWindow: Int? = nil
    var mcpServers: [McpServerInfo]? = nil
    var skills: [SkillInfo]? = nil
    /// Nested agent conversations; never rendered as top-level chats.
    var childThreads: [ChildThreadInfo]? = nil
    var shellAllowed: Bool? = true
    /// Held from this phone: the computer refuses its tool calls until resumed.
    var paused: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case sessionId, agent, projectId, taskId, computerId, title, cwd, branch, worktree
        case model, summary, accessLevel, state
        case startedAt, lastActivityAt, tokensSession, tokensLastTurn
        case contextTokensUsed, contextWindow, mcpServers, skills, childThreads, shellAllowed
        case paused
    }

    var isPaused: Bool { paused == true }

    var id: String { sessionId }

    /// How long this chat has been going.
    var elapsed: TimeInterval { max(0, (lastActivityAt - startedAt) / 1000) }
    var idleFor: TimeInterval { max(0, Date().timeIntervalSince1970 - lastActivityAt / 1000) }

    /// Conversation / session title from Mac. Project/repo is the list section
    /// header (`projectGroupTitle`) — never use the folder name as every row title.
    /// Never fall back to a raw session id / hex prefix (looked like foreign "code" chats).
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            let project = projectGroupTitle
            // Ignore slug/folder mirrors so rows stay distinct under the section.
            if t.caseInsensitiveCompare(project) != .orderedSame,
               t != cwd,
               t.caseInsensitiveCompare(sessionId) != .orderedSame {
                // UUID / hex blobs are not human titles (wrong-room residue).
                let uuid = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
                if t.range(of: uuid, options: .regularExpression) == nil {
                    return t
                }
            }
        }
        return L("Untitled chat")
    }

    /// Section header for Active / History lists: real workspace/repo name.
    /// Never invent a project from window titles ("Windows") or monitor cwd.
    var projectGroupTitle: String {
        guard let root = Self.projectRoot(from: cwd) else { return "No project" }
        return root
    }

    /// Stable sort key for grouping — normalized workspace root, or ungrouped.
    var projectGroupKey: String {
        if let root = Self.projectRoot(from: cwd) {
            return "proj:" + root.lowercased()
        }
        return "no-project"
    }

    /// Extract a trustworthy project/repo folder from cwd.
    /// Rejects home-only paths, Cursor UI slugs that aren't paths, and junk.
    private static func projectRoot(from cwd: String?) -> String? {
        guard var raw = cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        // Cursor sometimes publishes workspace slug "Users-foo-dev-bar".
        if !raw.contains("/"), raw.contains("-") {
            // Only treat as path-slug when it looks like Users-… / home-…
            if raw.hasPrefix("Users-") || raw.hasPrefix("home-") {
                raw = "/" + raw.replacingOccurrences(of: "-", with: "/")
            } else {
                return nil
            }
        }
        guard raw.contains("/") else { return nil }
        let parts = raw.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        // Home / Desktop / Downloads alone are not a project.
        let generic: Set<String> = [
            "Users", "home", "Desktop", "Documents", "Downloads",
            "tmp", "Temp", "Applications", "Library", "windows", "Windows",
        ]
        if generic.contains(last) { return nil }
        // Bare user home (/Users/name) → ungrouped.
        if parts.count <= 2, parts.first == "Users" || parts.first == "home" {
            return nil
        }
        return last
    }
}

enum SessionProjectGrouping {
    struct Group: Identifiable {
        let id: String
        let title: String
        let sessions: [SessionInfo]
    }

    /// Group chats by project/repo; within a group keep Mac activity order.
    static func groups(from sessions: [SessionInfo]) -> [Group] {
        var buckets: [(key: String, title: String, items: [SessionInfo])] = []
        var indexByKey: [String: Int] = [:]
        for session in sessions {
            let key = session.projectGroupKey
            if let idx = indexByKey[key] {
                buckets[idx].items.append(session)
            } else {
                indexByKey[key] = buckets.count
                buckets.append((key, session.projectGroupTitle, [session]))
            }
        }
        return buckets.map { Group(id: $0.key, title: $0.title, sessions: $0.items) }
    }
}

extension SessionInfo {
    /// Keep a usable chat row when a helper version omits optional metrics or
    /// publishes one malformed nested MCP/skill descriptor.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        agent = (try? c.decode(String.self, forKey: .agent)) ?? "codex"
        projectId = try? c.decode(String.self, forKey: .projectId)
        taskId = try? c.decode(String.self, forKey: .taskId)
        computerId = try? c.decode(String.self, forKey: .computerId)
        title = try? c.decode(String.self, forKey: .title)
        cwd = try? c.decode(String.self, forKey: .cwd)
        branch = try? c.decode(String.self, forKey: .branch)
        worktree = try? c.decode(String.self, forKey: .worktree)
        model = try? c.decode(String.self, forKey: .model)
        summary = try? c.decode(String.self, forKey: .summary)
        accessLevel = try? c.decode(String.self, forKey: .accessLevel)
        state = (try? c.decode(String.self, forKey: .state)) ?? "idle"

        let last = Self.decodeDouble(c, forKey: .lastActivityAt)
        let started = Self.decodeDouble(c, forKey: .startedAt)
        lastActivityAt = last ?? started ?? 0
        startedAt = started ?? lastActivityAt
        tokensSession = Self.decodeInt(c, forKey: .tokensSession) ?? 0
        tokensLastTurn = Self.decodeInt(c, forKey: .tokensLastTurn) ?? 0
        contextTokensUsed = Self.decodeInt(c, forKey: .contextTokensUsed)
        contextWindow = Self.decodeInt(c, forKey: .contextWindow)

        // Optional decorations must not make the entire session undecodable.
        mcpServers = try? c.decode([McpServerInfo].self, forKey: .mcpServers)
        skills = try? c.decode([SkillInfo].self, forKey: .skills)
        childThreads = Self.decodeChildThreads(c, forKey: .childThreads)
        shellAllowed = (try? c.decode(Bool.self, forKey: .shellAllowed)) ?? true
        paused = try? c.decode(Bool.self, forKey: .paused)
    }

    /// Decode children independently so one provider-specific malformed row
    /// cannot hide every otherwise valid nested agent conversation.
    private static func decodeChildThreads(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [ChildThreadInfo]? {
        guard c.contains(key),
              var nested = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
        var children: [ChildThreadInfo] = []
        while !nested.isAtEnd {
            guard let element = try? nested.superDecoder() else { break }
            if let child = try? ChildThreadInfo(from: element) {
                if children.count < 32 { children.append(child) }
            }
        }
        return children
    }

    private static func decodeDouble(_ c: KeyedDecodingContainer<CodingKeys>,
                                     forKey key: CodingKeys) -> Double? {
        if let value = try? c.decode(Double.self, forKey: key) { return value }
        if let value = try? c.decode(String.self, forKey: key) {
            if let number = Double(value) { return number }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date.timeIntervalSince1970 * 1000
            }
        }
        return nil
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>,
                                  forKey key: CodingKeys) -> Int? {
        if let value = try? c.decode(Int.self, forKey: key) { return value }
        if let value = try? c.decode(Double.self, forKey: key),
           let integer = exactWireInt(value) { return integer }
        if let value = try? c.decode(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
