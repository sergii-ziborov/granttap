import Foundation

struct AgentIntegrationInfo: Codable, Equatable, Identifiable {
    let agent: String
    let installed: Bool
    let hookConfigured: Bool
    /// The version that answers on that computer.
    var version: String? = nil
    /// The tool's own updater, as the computer would run it; absent when the
    /// computer will not run one.
    var updateCommand: String? = nil
    /// A newer copy already on that disk, which GrantTap already uses.
    var newerOnThisMac: String? = nil
    var updating: Bool? = nil

    var id: String { agent }
}

struct SessionsStatus: Decodable {
    let type: String           // "sessions.status"
    let machine: String
    /// `var` so inbound salvage can replace rows after stripping oversized blobs.
    var sessions: [SessionInfo]
    var history: [SessionInfo]?
    /// Embedded transcripts so the phone can render messages without waiting
    /// on a separate session.events round-trip.
    var activities: [SessionActivity]?
    let tokensRecent: Int
    let tokenWindowHours: Int
    var gatingEnabled: Bool?
    var excludedSessions: [String]?
    var autoAcceptDefault: String?
    var autoAcceptBySession: [String: String]?
    var autoAcceptPaused: Bool?
    var providerSettings: [String: Bool]?
    var meshEnabled: Bool?
    var configRevision: Int?
    var instanceEpoch: String?
    var globalMcpDisabled: [String]?
    var globalSkillsDisabled: [String]?
    var globalShellDisabled: Bool?
    var agents: [AgentIntegrationInfo]?
    let generatedAt: Double

    private enum CodingKeys: String, CodingKey {
        case type, machine, sessions, history, activities, tokensRecent, tokenWindowHours, tokensAllTime
        case gatingEnabled, excludedSessions, autoAcceptDefault, autoAcceptBySession, autoAcceptPaused
        case providerSettings, meshEnabled, configRevision, instanceEpoch
        case globalMcpDisabled, globalSkillsDisabled, globalShellDisabled
        case agents, generatedAt
    }

    init(type: String = "sessions.status",
         machine: String,
         sessions: [SessionInfo],
         history: [SessionInfo]? = nil,
         activities: [SessionActivity]? = nil,
         tokensRecent: Int,
         tokenWindowHours: Int,
         gatingEnabled: Bool? = nil,
         excludedSessions: [String]? = nil,
         autoAcceptDefault: String? = nil,
         autoAcceptBySession: [String: String]? = nil,
         autoAcceptPaused: Bool? = nil,
         providerSettings: [String: Bool]? = nil,
         meshEnabled: Bool? = nil,
         configRevision: Int? = nil,
         instanceEpoch: String? = nil,
         globalMcpDisabled: [String]? = nil,
         globalSkillsDisabled: [String]? = nil,
         globalShellDisabled: Bool? = nil,
         agents: [AgentIntegrationInfo]? = nil,
         generatedAt: Double) {
        self.type = type
        self.machine = machine
        self.sessions = sessions
        self.history = history
        self.activities = activities
        self.tokensRecent = tokensRecent
        self.tokenWindowHours = tokenWindowHours
        self.gatingEnabled = gatingEnabled
        self.excludedSessions = excludedSessions
        self.autoAcceptDefault = autoAcceptDefault
        self.autoAcceptBySession = autoAcceptBySession
        self.autoAcceptPaused = autoAcceptPaused
        self.providerSettings = providerSettings
        self.meshEnabled = meshEnabled
        self.configRevision = configRevision
        self.instanceEpoch = instanceEpoch
        self.globalMcpDisabled = globalMcpDisabled
        self.globalSkillsDisabled = globalSkillsDisabled
        self.globalShellDisabled = globalShellDisabled
        self.agents = agents
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "sessions.status"
        machine = (try? c.decode(String.self, forKey: .machine)) ?? ""
        // Lenient: one bad SessionInfo must not wipe the entire feed (Connected + 0 chats).
        sessions = Self.decodeSessionArray(c, forKey: .sessions) ?? []
        history = Self.decodeSessionArray(c, forKey: .history)
        activities = Self.decodeActivityArray(c, forKey: .activities)
        tokensRecent = Self.decodeInt(c, forKey: .tokensRecent)
            ?? Self.decodeInt(c, forKey: .tokensAllTime) ?? 0
        tokenWindowHours = Self.decodeInt(c, forKey: .tokenWindowHours) ?? 12
        gatingEnabled = try? c.decode(Bool.self, forKey: .gatingEnabled)
        excludedSessions = try? c.decode([String].self, forKey: .excludedSessions)
        autoAcceptDefault = try? c.decode(String.self, forKey: .autoAcceptDefault)
        autoAcceptBySession = try? c.decode([String: String].self, forKey: .autoAcceptBySession)
        autoAcceptPaused = try? c.decode(Bool.self, forKey: .autoAcceptPaused)
        providerSettings = try? c.decode([String: Bool].self, forKey: .providerSettings)
        meshEnabled = try? c.decode(Bool.self, forKey: .meshEnabled)
        configRevision = Self.decodeInt(c, forKey: .configRevision)
        instanceEpoch = try? c.decode(String.self, forKey: .instanceEpoch)
        globalMcpDisabled = try? c.decode([String].self, forKey: .globalMcpDisabled)
        globalSkillsDisabled = try? c.decode([String].self, forKey: .globalSkillsDisabled)
        globalShellDisabled = try? c.decode(Bool.self, forKey: .globalShellDisabled)
        agents = try? c.decode([AgentIntegrationInfo].self, forKey: .agents)
        generatedAt = (try? c.decode(Double.self, forKey: .generatedAt))
            ?? Date().timeIntervalSince1970 * 1000
    }

    private static func decodeSessionArray(_ c: KeyedDecodingContainer<CodingKeys>,
                                          forKey key: CodingKeys) -> [SessionInfo]? {
        guard c.contains(key) else { return nil }
        if let all = try? c.decode([SessionInfo].self, forKey: key) { return all }
        guard var nested = try? c.nestedUnkeyedContainer(forKey: key) else { return [] }
        var kept: [SessionInfo] = []
        while !nested.isAtEnd {
            guard let element = try? nested.superDecoder() else { break }
            if let item = try? SessionInfo(from: element) {
                kept.append(item)
            }
        }
        return kept
    }

    private static func decodeActivityArray(_ c: KeyedDecodingContainer<CodingKeys>,
                                            forKey key: CodingKeys) -> [SessionActivity]? {
        guard c.contains(key) else { return nil }
        if let all = try? c.decode([SessionActivity].self, forKey: key) { return all }
        guard var nested = try? c.nestedUnkeyedContainer(forKey: key) else { return [] }
        var kept: [SessionActivity] = []
        while !nested.isAtEnd {
            guard let element = try? nested.superDecoder() else { break }
            if let item = try? SessionActivity(from: element) {
                kept.append(item)
            }
        }
        return kept
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
