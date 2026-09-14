import Foundation

struct ActivityEntry: Codable, Identifiable, Equatable {
    let id: String
    let kind: String              // "user" | "message" | "tool" | "final" | "status"
    let text: String
    let createdAt: Double
    var toolName: String? = nil
    var mcpServer: String? = nil
    var skill: String? = nil
    var capabilities: [ObservedCapability]? = nil
    var durationMs: Int? = nil
    var outcome: CapabilityOutcome? = nil
    var errorClass: String? = nil
    /// Provider-native nested agent conversation. Nil means the root chat.
    var childThreadId: String? = nil
    var childThreadTitle: String? = nil
    var childThreadDepth: Int? = nil
    /// Rough context tokens for this tool call (args/result), not billing.
    var estimatedContextTokens: Int? = nil
    /// Filenames sent with this message. Names only — never paths or bytes.
    var attachments: [String]? = nil
    /// What a file tool changed, as git counts it: lines in, lines out.
    var linesAdded: Int? = nil
    var linesRemoved: Int? = nil
    /// The change itself, bounded: lines the computer prefixed with +, − or a
    /// space, secrets already removed there.
    var diffPreview: String? = nil
    /// What the agent said the call was for, when the tool takes a description.
    var summary: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, toolName, mcpServer, skill
        case capabilities, durationMs, estimatedContextTokens, outcome, errorClass
        case childThreadId, childThreadTitle, childThreadDepth, attachments
        case linesAdded, linesRemoved, diffPreview, summary
    }

    /// "+12 −3" material, when the call changed a file at all.
    var diffStats: (added: Int, removed: Int)? {
        let added = max(0, linesAdded ?? 0)
        let removed = max(0, linesRemoved ?? 0)
        return added > 0 || removed > 0 ? (added, removed) : nil
    }

    init(id: String, kind: String, text: String, createdAt: Double,
         toolName: String? = nil, mcpServer: String? = nil, skill: String? = nil,
         capabilities: [ObservedCapability]? = nil, durationMs: Int? = nil,
         outcome: CapabilityOutcome? = nil, errorClass: String? = nil,
         estimatedContextTokens: Int? = nil, childThreadId: String? = nil,
         childThreadTitle: String? = nil, childThreadDepth: Int? = nil,
         attachments: [String]? = nil, linesAdded: Int? = nil, linesRemoved: Int? = nil,
         diffPreview: String? = nil, summary: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.toolName = toolName
        self.mcpServer = mcpServer
        self.skill = skill
        self.capabilities = capabilities
        self.durationMs = durationMs
        self.outcome = outcome
        self.errorClass = errorClass
        self.estimatedContextTokens = estimatedContextTokens
        self.childThreadId = childThreadId
        self.childThreadTitle = childThreadTitle
        self.childThreadDepth = childThreadDepth
        self.attachments = attachments
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.diffPreview = diffPreview
        self.summary = summary
    }

    /// Lenient: one bad optional (capabilities enum, etc.) must not drop the row.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "message"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        if let d = try? c.decode(Double.self, forKey: .createdAt) {
            createdAt = d
        } else if let i = try? c.decode(Int.self, forKey: .createdAt) {
            createdAt = Double(i)
        } else {
            createdAt = 0
        }
        toolName = try? c.decode(String.self, forKey: .toolName)
        mcpServer = try? c.decode(String.self, forKey: .mcpServer)
        skill = try? c.decode(String.self, forKey: .skill)
        capabilities = try? c.decode([ObservedCapability].self, forKey: .capabilities)
        durationMs = Self.decodeNonnegativeWireInt(c, forKey: .durationMs)
        outcome = try? c.decode(CapabilityOutcome.self, forKey: .outcome)
        errorClass = try? c.decode(String.self, forKey: .errorClass)
        estimatedContextTokens = Self.decodeNonnegativeWireInt(
            c,
            forKey: .estimatedContextTokens
        )
        childThreadId = try? c.decode(String.self, forKey: .childThreadId)
        childThreadTitle = try? c.decode(String.self, forKey: .childThreadTitle)
        childThreadDepth = try? c.decode(Int.self, forKey: .childThreadDepth)
        attachments = try? c.decode([String].self, forKey: .attachments)
        linesAdded = Self.decodeNonnegativeWireInt(c, forKey: .linesAdded)
        linesRemoved = Self.decodeNonnegativeWireInt(c, forKey: .linesRemoved)
        diffPreview = (try? c.decode(String.self, forKey: .diffPreview)).flatMap { $0.count <= 4_000 ? $0 : String($0.prefix(4_000)) }
        summary = (try? c.decode(String.self, forKey: .summary)).map { String($0.prefix(200)) }
    }

    private static func decodeNonnegativeWireInt(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? c.decode(Int.self, forKey: key), value >= 0 {
            return value
        }
        if let value = try? c.decode(Double.self, forKey: key),
           let integer = exactWireInt(value), integer >= 0 {
            return integer
        }
        return nil
    }
}

struct ObservedCapability: Codable, Equatable {
    let kind: CapabilityUsageKind
    let name: String
    let toolName: String
    /// One-line, bounded prefix of a CLI command. Never contains full output.
    var commandPreview: String? = nil
    var estimatedContextTokens: Int?
    var estimatedBaselineTokens: Int?
    var durationMs: Int?
    var outcome: CapabilityOutcome? = nil
    var errorClass: String? = nil
    var resource: CapabilityResourceUsage? = nil
}

struct CapabilityChatTarget: Codable, Equatable {
    let kind: String              // "chat"
    let roomId: String
    let sessionId: String
}

struct RemoteCapabilityUsageEvent: Codable {
    let sourceId: String
    /// Informational wire value. The authenticated relay room remains authoritative.
    var roomId: String? = nil
    var sessionId: String?
    var agent: String? = nil
    var model: String? = nil
    let kind: CapabilityUsageKind
    let name: String
    let toolName: String
    var commandPreview: String? = nil
    var deepLinkTarget: CapabilityChatTarget? = nil
    let createdAt: Double
    var estimatedContextTokens: Int?
    var estimatedBaselineTokens: Int?
    var durationMs: Int?
    var outcome: CapabilityOutcome? = nil
    var errorClass: String? = nil
    var resource: CapabilityResourceUsage? = nil
}

/// What a period actually contained, counted on the computer.
///
/// The event list is bounded by a byte budget, so on a busy computer it holds
/// only the newest hours. Counting it turned "last 30 days" into "the last
/// eighty calls" and made a capability used yesterday read as never used.
struct CapabilityUsageTotal: Codable, Equatable {
    let windowHours: Int
    let kind: CapabilityUsageKind
    /// Absent on the roll-up row for a whole kind.
    var name: String? = nil
    let count: Int
    let failures: Int
    let cancelled: Int
    let lastUsedAt: Double
}

struct CapabilityUsageStatus: Codable {
    let type: String              // "capability.usage.status"
    let events: [RemoteCapabilityUsageEvent]
    var totals: [CapabilityUsageTotal]? = nil
    let generatedAt: Double
}

struct SessionActivity: Codable, Equatable {
    let type: String              // "session.activity"
    let sessionId: String
    let agent: String
    let state: String
    /// Set when the entries are one agent conversation of the chat, fetched
    /// whole, rather than the chat's own window.
    var threadId: String? = nil
    let entries: [ActivityEntry]
    let generatedAt: Double

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, agent, state, threadId, entries, generatedAt
    }

    init(type: String = "session.activity", sessionId: String, agent: String,
         state: String, threadId: String? = nil, entries: [ActivityEntry], generatedAt: Double) {
        self.type = type
        self.sessionId = sessionId
        self.agent = agent
        self.state = state
        self.threadId = threadId
        self.entries = entries
        self.generatedAt = generatedAt
    }

    /// Keep every decodable entry; one malformed tool row must not blank Full chat.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "session.activity"
        sessionId = try c.decode(String.self, forKey: .sessionId)
        agent = (try? c.decode(String.self, forKey: .agent)) ?? "codex"
        state = (try? c.decode(String.self, forKey: .state)) ?? "idle"
        threadId = try? c.decode(String.self, forKey: .threadId)
        if let d = try? c.decode(Double.self, forKey: .generatedAt) {
            generatedAt = d
        } else if let i = try? c.decode(Int.self, forKey: .generatedAt) {
            generatedAt = Double(i)
        } else {
            generatedAt = Date().timeIntervalSince1970 * 1000
        }
        if let all = try? c.decode([ActivityEntry].self, forKey: .entries) {
            entries = all.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.kind == "tool" }
        } else if var nested = try? c.nestedUnkeyedContainer(forKey: .entries) {
            var kept: [ActivityEntry] = []
            while !nested.isAtEnd {
                guard let element = try? nested.superDecoder() else { break }
                if let item = try? ActivityEntry(from: element),
                   !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || item.kind == "tool" {
                    kept.append(item)
                }
            }
            entries = kept
        } else {
            entries = []
        }
    }
}

/// Per-task key grant, itself protected by the device-to-device NaCl box.
