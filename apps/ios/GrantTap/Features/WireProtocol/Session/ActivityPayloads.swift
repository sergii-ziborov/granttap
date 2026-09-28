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
    var images: [MessageImageAttachment]? = nil
    /// What a file tool changed, as git counts it: lines in, lines out.
    var linesAdded: Int? = nil
    var linesRemoved: Int? = nil
    /// The change itself, bounded: lines the computer prefixed with +, − or a
    /// space, secrets already removed there.
    var diffPreview: String? = nil
    /// What the agent said the call was for, when the tool takes a description.
    var summary: String? = nil

    var callText: String? = nil
    var resultText: String? = nil
    var detailTruncated: Bool? = nil
    var fileChanges: [RecordedFileChange]? = nil
    var fileChangesComplete: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, toolName, mcpServer, skill
        case capabilities, durationMs, estimatedContextTokens, outcome, errorClass
        case childThreadId, childThreadTitle, childThreadDepth, attachments
        case linesAdded, linesRemoved, diffPreview, summary, images
        case callText, resultText, detailTruncated, fileChanges, fileChangesComplete
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
         diffPreview: String? = nil, summary: String? = nil,
         images: [MessageImageAttachment]? = nil, callText: String? = nil,
         resultText: String? = nil, detailTruncated: Bool? = nil,
         fileChanges: [RecordedFileChange]? = nil, fileChangesComplete: Bool? = nil) {
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
        self.images = images
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.diffPreview = diffPreview
        self.summary = summary
        self.callText = callText
        self.resultText = resultText
        self.detailTruncated = detailTruncated
        self.fileChanges = fileChanges
        self.fileChangesComplete = fileChangesComplete
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
        images = (try? c.decode([MessageImageAttachment].self, forKey: .images))
            .map { Array($0.filter(\.isValid).prefix(32)) }
        linesAdded = Self.decodeNonnegativeWireInt(c, forKey: .linesAdded)
        linesRemoved = Self.decodeNonnegativeWireInt(c, forKey: .linesRemoved)
        diffPreview = (try? c.decode(String.self, forKey: .diffPreview)).flatMap { $0.count <= 4_000 ? $0 : String($0.prefix(4_000)) }
        summary = (try? c.decode(String.self, forKey: .summary)).map { String($0.prefix(200)) }
        callText = (try? c.decode(String.self, forKey: .callText)).map { String($0.prefix(16_384)) }
        resultText = (try? c.decode(String.self, forKey: .resultText)).map { String($0.prefix(16_384)) }
        detailTruncated = try? c.decode(Bool.self, forKey: .detailTruncated)
        fileChanges = (try? c.decode([RecordedFileChange].self, forKey: .fileChanges)).map { Array($0.prefix(64)) }
        fileChangesComplete = try? c.decode(Bool.self, forKey: .fileChangesComplete)
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
