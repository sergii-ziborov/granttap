import Foundation

// Wire protocol — mirrors packages/protocol/schema.ts exactly.
// Payloads are E2E-encrypted; only the Envelope's routing fields are cleartext.

enum Role: String, Codable { case machine, phone }

struct Envelope: Codable {
    var v: Int = 1
    var room: String
    var from: Role
    var to: String        // "machine" | "phone" | "all"
    var senderId: String
    var deliveryId: String?
    var wake: Bool?
    var expiresAt: Double?
    var nonce: String     // base64
    var box: String       // base64 (sealed payload)
}

enum Risk: String, Codable { case low, medium, high }

/// Visible severity for Allow UI (phone + Cloudflare). Not a chat message.
enum DangerLevel: String, Codable {
    case safe, caution, dangerous, destructive
}

struct ApprovalRequest: Codable, Identifiable {
    let type: String              // "approval.request"
    let requestId: String
    let agent: String             // "claude" | "codex" | ...
    let kind: String
    let tool: String
    let title: String
    let command: String?
    let cwd: String?
    let sessionId: String?
    let risk: Risk
    let danger: DangerLevel?
    let createdAt: Double
    var id: String { requestId }
}

enum ActionRequestKind: String, Codable {
    case permission, yesNo = "yes_no", question, deliveryRetry = "delivery_retry"
}

enum ActionRequestRisk: String, Codable {
    case safe, caution, dangerous, destructive
}

enum ActionRequestState: String, Codable {
    case pending, submitting, resolved, failed
}

struct ActionRequest: Codable, Identifiable {
    let id: String
    var sessionId: String?
    var agent: String?
    let kind: ActionRequestKind
    let title: String
    var detail: String?
    var command: String?
    let risk: ActionRequestRisk
    var state: ActionRequestState
    let createdAt: Double
    var expiresAt: Double?
}

struct ApprovalDecision: Codable {
    let type: String              // "approval.decision"
    let requestId: String
    let decision: String          // "allow" | "deny"
    var note: String?
    var decidedBy: String?
    var sessionId: String?
    let decidedAt: Double
}

/// machine -> phone: dismiss pending Allow / question cards.
struct ApprovalCancel: Codable {
    let type: String              // "approval.cancel"
    var requestId: String?
    var cancelAll: Bool?
    var reason: String?
    let createdAt: Double
}

/// machine -> phone: authoritative completion of one approval decision.
struct ApprovalResolved: Codable {
    let type: String              // "approval.resolved"
    let requestId: String
    let status: String            // "applied" | "cancelled" | "expired"
    var decision: String?         // "allow" | "deny"
    var decidedBy: String?
    var note: String?
    var sessionId: String?
    var nativeUiCleared: Bool?
    let resolvedAt: Double
}

/// Exact registry entry covered by an approval status snapshot.
struct ApprovalStatusScope: Codable {
    let requestId: String
    var sessionId: String?
}

/// machine -> phone: current approval snapshot for one source room.
struct ApprovalsStatus: Codable {
    let type: String              // "approvals.status"
    let pending: [ApprovalRequest]
    /// Legacy global-authority bit. New machines send false so older apps merge.
    let complete: Bool
    /// Exact registered scopes whose pending/terminal state is authoritative.
    var covered: [ApprovalStatusScope]?
    var actions: [ActionRequest]?
    let generatedAt: Double
}

struct UserMessage: Codable {
    let type: String              // "user.message"
    var messageId: String?
    let text: String
    var agent: String?            // "codex" | "claude" for a new task
    var cwd: String?              // explicit known workspace for a new task; nil = GrantTap general workspace
    var requestId: String?
    var sessionId: String?
    var attachments: [UserAttachment]?
    /// Attachments that went ahead of this message, by id.
    var attachmentRefs: [UserAttachmentRef]?
    var preferredMcp: String?
    var skill: String?
    var projectId: String? = nil
    /// Model for this turn; nil keeps whatever the chat already uses.
    var model: String?
    /// Provider permission mode for this turn; nil keeps the chat's own.
    var permissionMode: String?
    /// How hard the model should work on this turn; nil keeps the chat's own.
    var effort: String?
    let createdAt: Double
}

struct DeliveryReceipt: Codable {
    let type: String              // "delivery.receipt"
    let messageId: String
    var sessionId: String?
    let status: String            // "accepted" | "rejected"
    var error: String?
    let receivedAt: Double
}

struct UserAttachment: Codable {
    let name: String
    let mimeType: String
    let data: String              // base64, encrypted with the rest of the payload
}

/// An attachment that went ahead of its message, named by id in the message.
struct UserAttachmentRef: Codable, Equatable {
    let attachmentId: String
    let name: String
    let mimeType: String
}

/// The attachment itself, sent the moment it was picked so the message that
/// follows travels light. Sealed like everything else in the room.
struct UserAttachmentUpload: Codable, Equatable {
    let type: String              // "user.attachment"
    let attachmentId: String
    let name: String
    let mimeType: String
    let data: String              // base64
    let createdAt: Double
}

struct AgentEvent: Codable {
    let type: String              // "agent.event"
    let text: String
    var requestId: String?
    var kind: String?             // "question" | "status" | "response"
    var sessionId: String?
    /// Exact user.message.messageId that caused this event, when applicable.
    var originMessageId: String? = nil
    let createdAt: Double
}

struct SessionSubscription: Codable {
    let type: String              // "session.subscribe"
    let sessionId: String
    let active: Bool
    let createdAt: Double
}

struct SessionEventsRequest: Codable {
    let type: String              // "session.events"
    let sessionId: String
    /// One agent conversation of the chat, whole, instead of the chat's window.
    var threadId: String? = nil
    let createdAt: Double
}

struct SessionsRefresh: Codable {
    let type: String              // "sessions.refresh"
    let createdAt: Double
}

struct SessionAccessSet: Codable {
    let type: String              // "session.access.set"
    let sessionId: String
    let accessLevel: String       // "read-only" | "workspace" | "full"
    let createdAt: Double
}

struct SessionMcpSet: Codable {
    let type: String              // "session.mcp.set"
    var scope: String?
    var sessionId: String?
    let serverName: String
    let allowed: Bool
    let createdAt: Double
}

struct SessionSkillSet: Codable {
    let type: String              // "session.skill.set"
    var scope: String?
    var sessionId: String?
    let skillName: String
    let allowed: Bool
    let createdAt: Double
}

struct SessionShellSet: Codable {
    let type: String              // "session.shell.set"
    var scope: String?
    var sessionId: String?
    let allowed: Bool
    let createdAt: Double
}

struct SessionCompact: Codable {
    let type: String              // "session.compact"
    let sessionId: String
    let createdAt: Double
}

struct SessionCompactResult: Codable {
    let type: String              // "session.compact.result"
    let sessionId: String
    let ok: Bool
    let message: String
    let createdAt: Double
}

/// Pause or resume one chat. A pause is a hold the computer enforces on every
/// tool call the chat makes; a resume lifts it, and with `continue` also asks
/// the agent to carry on where it stopped.
struct SessionControl: Codable, Equatable {
    let type: String              // "session.control"
    let sessionId: String
    let action: String            // "pause" | "resume"
    var `continue`: Bool? = nil
    let createdAt: Double
}

struct SessionControlResult: Codable, Equatable {
    let type: String              // "session.control.result"
    let sessionId: String
    let action: String
    let ok: Bool
    let message: String
    let createdAt: Double
}

/// Ask one computer to run a tool's own updater. The phone names the tool;
/// the command is the computer's, fixed by how the tool was installed.
struct ToolUpdate: Codable, Equatable {
    let type: String              // "tool.update"
    let agent: String
    let requestId: String
    let createdAt: Double
}

struct ToolUpdateResult: Codable, Equatable {
    let type: String              // "tool.update.result"
    let agent: String
    let requestId: String
    let ok: Bool
    var before: String? = nil
    var after: String? = nil
    var command: String? = nil
    let message: String
    var output: String? = nil
    let createdAt: Double
}
