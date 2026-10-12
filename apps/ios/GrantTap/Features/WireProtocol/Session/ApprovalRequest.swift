import Foundation

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
    var details: String? = nil
    var projectId: String? = nil
    var policyRevision: Int? = nil
    var inputFingerprint: String? = nil
    var questions: [ApprovalQuestion]? = nil
    var id: String { requestId }
}

struct ApprovalQuestion: Codable {
    let question: String
    let header: String
    let options: [ApprovalQuestionOption]
    let multiSelect: Bool
}

struct ApprovalQuestionOption: Codable {
    let label: String
    let description: String
}

