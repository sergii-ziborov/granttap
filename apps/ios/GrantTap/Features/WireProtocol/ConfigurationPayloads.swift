import Foundation

struct ConfigSet: Codable {
    let type: String           // "config.set"
    var enabled: Bool?
    var excludeSession: String?
    var includeSession: String?
    var autoAcceptDefault: String?
    var autoAcceptSession: AutoAcceptSessionSet?
    var autoAcceptPaused: Bool?
    var provider: String? = nil
    var providerEnabled: Bool? = nil
    var meshEnabled: Bool? = nil
    var operationId: String? = nil
    var baseRevision: Int? = nil
    var expiresAt: Double? = nil
    var payloadDigest: String? = nil
    var instanceEpoch: String? = nil
    let createdAt: Double
}

struct TaskCreate: Codable {
    let type: String
    let operationId: String
    let text: String
    let cwd: String
    var agent: String? = nil
    var model: String? = nil
    var instanceEpoch: String? = nil
    var parentSessionId: String? = nil
    var attachments: [UserAttachment]? = nil
    var attachmentRefs: [UserAttachmentRef]? = nil
    let createdAt: Double
}

struct AutoAcceptSessionSet: Codable {
    let sessionId: String
    /// nil clears the per-session override (inherit device default).
    let level: String?
}

/// GrantTap Layer B auto-accept levels (Mac hook enforcement).
enum AutoAcceptLevel: String, CaseIterable, Identifiable {
    case ask
    case safe
    case exceptPush = "except_push"
    case exceptDestructive = "except_destructive"
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return L("Ask always")
        case .safe: return L("Safe only")
        case .exceptPush: return L("All except push")
        case .exceptDestructive: return L("All except destructive")
        case .full: return L("Full auto")
        }
    }

    var blurb: String {
        switch self {
        case .ask: return L("Every tool asks on iPhone")
        case .safe: return L("Auto-allow read/search; ask for edits and shell")
        case .exceptPush: return L("Auto-allow work; ask for push, publish, and destructive")
        case .exceptDestructive: return L("Auto-allow including plain push; ask for force and destructive")
        case .full: return L("Auto-allow everything GrantTap would have asked")
        }
    }

    static func parse(_ raw: String?) -> AutoAcceptLevel {
        AutoAcceptLevel(rawValue: raw ?? "") ?? .ask
    }
}

struct Hello: Codable {
    let type: String              // "hello"
    let role: Role
    let deviceName: String
    var recoverPeer: Bool? = nil
    let createdAt: Double
}

/// Peek at the `type` discriminator without committing to a concrete payload.
struct PayloadKind: Codable { let type: String }

enum Payloads {
    static func decision(_ requestId: String, _ decision: String, by: String,
                         sessionId: String?) -> ApprovalDecision {
        ApprovalDecision(
            type: "approval.decision",
            requestId: requestId,
            decision: decision,
            note: nil,
            decidedBy: by,
            sessionId: sessionId,
            decidedAt: Date().timeIntervalSince1970 * 1000
        )
    }
    static func hello(_ deviceName: String, role: Role = .phone, recoverPeer: Bool = false) -> Hello {
        Hello(type: "hello", role: role, deviceName: deviceName,
              recoverPeer: recoverPeer ? true : nil,
              createdAt: Date().timeIntervalSince1970 * 1000)
    }
    static func message(_ text: String, messageId: String, agent: String?, cwd: String?,
                        sessionId: String?, requestId: String?,
                        attachments: [UserAttachment] = [], attachmentRefs: [UserAttachmentRef] = [],
                        preferredMcp: String? = nil,
                        skill: String? = nil, model: String? = nil,
                        permissionMode: String? = nil,
                        effort: String? = nil) -> UserMessage {
        UserMessage(type: "user.message", messageId: messageId, text: text, agent: agent,
                    cwd: cwd, requestId: requestId, sessionId: sessionId,
                    attachments: attachments.isEmpty ? nil : attachments,
                    attachmentRefs: attachmentRefs.isEmpty ? nil : attachmentRefs,
                    preferredMcp: preferredMcp, skill: skill,
                    model: model, permissionMode: permissionMode, effort: effort,
                    createdAt: Date().timeIntervalSince1970 * 1000)
    }
}
