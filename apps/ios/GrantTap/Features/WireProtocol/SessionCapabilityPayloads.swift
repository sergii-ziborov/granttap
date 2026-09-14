import Foundation

struct SessionKeyGrant: Codable {
    let type: String              // "session.key.grant"
    let sessionId: String
    let key: String               // base64url, 256 random bits
    var purpose: String? = nil     // phone -> machine: "task" | "project"
    let createdAt: Double
}

/// A task payload with a second authenticated-encryption layer.
struct SessionSealed: Codable {
    let type: String              // "session.sealed"
    let sessionId: String
    let nonce: String
    let box: String
    let createdAt: Double
}

struct McpIconInfo: Codable, Equatable {
    let src: String
    var mimeType: String?
    var sizes: [String]?
    var theme: String?
    var sourceOrigin: String?
}

struct McpServerInfo: Codable, Identifiable, Equatable {
    let name: String
    let configuredEnabled: Bool
    var allowed: Bool
    var authStatus: String?
    var title: String?
    var websiteUrl: String?
    var version: String?
    var icons: [McpIconInfo]?
    var metadataSource: String?
    var id: String { name }
}

struct SkillInfo: Codable, Identifiable, Equatable {
    let name: String
    var description: String?
    var allowed: Bool? = true
    var id: String { name }
}

/// A provider-native agent/subagent conversation contained by one visible chat.
struct ChildThreadInfo: Codable, Identifiable, Equatable {
    let threadId: String
    let parentThreadId: String
    var title: String?
    var agentName: String? = nil
    var model: String? = nil
    let depth: Int
    var state: String
    let startedAt: Double
    var lastActivityAt: Double
    let tokensSession: Int
    let tokensLastTurn: Int
    var contextTokensUsed: Int? = nil
    var contextWindow: Int? = nil
    var id: String { threadId }
}

/// JSONDecoder may surface non-conforming numbers as Double. Convert only when
/// the value is finite, integral, in range, and exactly representable as Int.
func exactWireInt(_ value: Double) -> Int? {
    guard value.isFinite,
          value.rounded(.towardZero) == value,
          value >= Double(Int.min),
          value <= Double(Int.max),
          let integer = Int(exactly: value) else { return nil }
    return integer
}

/// One live chat on a machine, with the agent's own token numbers.
