import Foundation

// Shared phone↔watch payloads (this file is compiled into BOTH targets).
//
// The watch has no relay socket of its own — watchOS can't hold a WebSocket —
// so the iPhone is the hub: it holds the relay connection and mirrors state to
// the watch over WatchConnectivity, and the watch sends decisions/replies back
// through the phone.

/// A permission request waiting for a tap.
struct WatchApproval: Codable, Identifiable, Equatable {
    let id: String            // requestId
    let agent: String
    let title: String
    var command: String?
    let risk: String          // "low" | "medium" | "high"
    var cwd: String?
    var sessionId: String?
    /// nil decodes old phone snapshots as the honest default: not yet submitted.
    var waitingForMachine: Bool? = nil
}

/// A correlated open question from the GrantTap MCP server.
struct WatchQuestion: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    var sessionId: String?
}

enum HumanAttentionKind: String, Codable {
    case approval
    case question
    case deliveryFailure
    case meshQuestion
    case meshConflict
    case meshHandoff
    case meshFailure
}

enum HumanAttentionAction: String, Codable {
    case decision
    case reply
    case retryOnPhone
    case meshDecision
    case meshReply
    case openPhone
}

/// One bounded decision surface shared by iPhone notifications, Needs You, and Watch.
struct HumanAttentionItem: Codable, Identifiable, Equatable {
    let id: String
    let kind: HumanAttentionKind
    let action: HumanAttentionAction
    let title: String
    var detail: String? = nil
    var agent: String? = nil
    var command: String? = nil
    var risk: String? = nil
    var sessionId: String? = nil
    var projectId: String? = nil
    var taskId: String? = nil
    var createdAt: Double = 0
    var waitingForMachine: Bool? = nil
}

/// A live chat, trimmed to what the wrist shows.
struct WatchSession: Codable, Identifiable, Equatable {
    let id: String            // sessionId
    let agent: String
    var title: String
    let state: String         // "working" | "waiting" | "idle"
    let tokensSession: Int
    let tokensLastTurn: Int
    let elapsedSec: Int
    var contextTokensUsed: Int? = nil
    var contextWindow: Int? = nil
    /// Preserves the phone catalog's recency order across WatchConnectivity.
    var lastActivityAt: Double? = nil
}

struct WatchActivityEntry: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let text: String
    let createdAt: Double
}

struct WatchActivity: Codable, Equatable {
    let sessionId: String
    let agent: String
    let state: String
    let entries: [WatchActivityEntry]
}

struct WatchAgentIntegration: Codable, Identifiable, Equatable {
    let agent: String
    let installed: Bool
    let hookConfigured: Bool

    var id: String { agent }
}

/// The whole picture the phone pushes to the watch (latest-state wins).
struct WatchState: Codable, Equatable {
    var attention: [HumanAttentionItem] = []
    var approvals: [WatchApproval] = []
    var questions: [WatchQuestion] = []
    var sessions: [WatchSession] = []
    var activities: [WatchActivity] = []
    var agents: [WatchAgentIntegration] = []
    var machine: String = ""
    var connected: Bool = false
    var stamp: Double = 0     // forces a fresh applicationContext each push

    init(attention: [HumanAttentionItem] = [],
         approvals: [WatchApproval] = [], questions: [WatchQuestion] = [],
         sessions: [WatchSession] = [], activities: [WatchActivity] = [],
         agents: [WatchAgentIntegration] = [],
         machine: String = "", connected: Bool = false, stamp: Double = 0) {
        self.attention = attention
        self.approvals = approvals
        self.questions = questions
        self.sessions = sessions
        self.activities = activities
        self.agents = agents
        self.machine = machine
        self.connected = connected
        self.stamp = stamp
    }

    private enum CodingKeys: String, CodingKey {
        case attention, approvals, questions, sessions, activities, agents, machine, connected, stamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attention = try c.decodeIfPresent([HumanAttentionItem].self, forKey: .attention) ?? []
        approvals = try c.decodeIfPresent([WatchApproval].self, forKey: .approvals) ?? []
        questions = try c.decodeIfPresent([WatchQuestion].self, forKey: .questions) ?? []
        sessions = try c.decodeIfPresent([WatchSession].self, forKey: .sessions) ?? []
        activities = try c.decodeIfPresent([WatchActivity].self, forKey: .activities) ?? []
        agents = try c.decodeIfPresent([WatchAgentIntegration].self, forKey: .agents) ?? []
        machine = try c.decodeIfPresent(String.self, forKey: .machine) ?? ""
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        stamp = try c.decodeIfPresent(Double.self, forKey: .stamp) ?? 0
    }

    /// Old phone snapshots remain useful after a watch app update.
    var humanAttention: [HumanAttentionItem] {
        if !attention.isEmpty { return attention.sorted { $0.createdAt > $1.createdAt } }
        let legacyApprovals = approvals.map {
            HumanAttentionItem(
                id: $0.id, kind: .approval, action: .decision, title: $0.title,
                agent: $0.agent, command: $0.command, risk: $0.risk,
                sessionId: $0.sessionId, waitingForMachine: $0.waitingForMachine
            )
        }
        let legacyQuestions = questions.map {
            HumanAttentionItem(
                id: $0.id, kind: .question, action: .reply, title: $0.text,
                sessionId: $0.sessionId
            )
        }
        return legacyApprovals + legacyQuestions
    }
}

/// Watch → phone: a decision, or a message typed/dictated on the wrist.
struct WatchAction: Codable {
    enum Kind: String, Codable {
        case decision, message, meshDecision, meshAnswer, subscription, refresh
    }
    let kind: Kind
    var requestId: String?
    var decision: String?     // "allow" | "deny"
    var text: String?
    var sessionId: String?
    var active: Bool?
    var agent: String?
    var source: String?
    var by: String = "watch"

    static func decision(_ requestId: String, _ decision: String,
                         sessionId: String? = nil) -> WatchAction {
        WatchAction(kind: .decision, requestId: requestId, decision: decision,
                    sessionId: sessionId)
    }
    static func message(_ text: String, sessionId: String?, requestId: String? = nil,
                        agent: String? = nil) -> WatchAction {
        WatchAction(kind: .message, requestId: requestId, text: text,
                    sessionId: sessionId, agent: agent)
    }
    /// Guidance typed from a permission card is an ordinary task follow-up.
    /// Reusing the approval requestId would route it into the yes/no waiter,
    /// where arbitrary text is intentionally not consumed.
    static func canSendPermissionFollowUp(sessionId: String?) -> Bool {
        scopedPermissionSessionId(sessionId) != nil
    }
    static func permissionFollowUp(_ text: String, sessionId: String?,
                                   agent: String) -> WatchAction? {
        guard let sessionId = scopedPermissionSessionId(sessionId) else {
            return nil
        }
        return message(text, sessionId: sessionId,
                       agent: AgentIdentity.normalize(agent))
    }
    /// A GrantTap MCP question has an open-text waiter keyed by requestId.
    static func questionReply(_ text: String, sessionId: String?,
                              requestId: String) -> WatchAction {
        message(text, sessionId: sessionId, requestId: requestId)
    }
    static func meshDecision(_ eventId: String, allow: Bool) -> WatchAction {
        WatchAction(kind: .meshDecision, requestId: eventId,
                    decision: allow ? "allow" : "deny")
    }
    static func meshAnswer(_ text: String, eventId: String) -> WatchAction {
        WatchAction(kind: .meshAnswer, requestId: eventId, text: text)
    }
    static func subscription(_ sessionId: String, active: Bool, source: String = "detail") -> WatchAction {
        WatchAction(kind: .subscription, sessionId: sessionId, active: active, source: source)
    }
    static func newTask(_ text: String, agent: String) -> WatchAction {
        WatchAction(kind: .message, text: text, agent: agent)
    }
    static func refresh() -> WatchAction {
        WatchAction(kind: .refresh)
    }

    private static func scopedPermissionSessionId(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 }
    }
}
