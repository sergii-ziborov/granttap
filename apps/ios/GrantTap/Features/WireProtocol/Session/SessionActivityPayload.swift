import Foundation

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
    var history: TranscriptHistoryPage? = nil

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, agent, state, threadId, entries, generatedAt, history
    }

    init(type: String = "session.activity", sessionId: String, agent: String,
         state: String, threadId: String? = nil, entries: [ActivityEntry], generatedAt: Double,
         history: TranscriptHistoryPage? = nil) {
        self.type = type
        self.sessionId = sessionId
        self.agent = agent
        self.state = state
        self.threadId = threadId
        self.entries = entries
        self.generatedAt = generatedAt
        self.history = history
    }

    /// Keep every decodable entry; one malformed tool row must not blank Full chat.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "session.activity"
        sessionId = try c.decode(String.self, forKey: .sessionId)
        agent = (try? c.decode(String.self, forKey: .agent)) ?? "codex"
        state = (try? c.decode(String.self, forKey: .state)) ?? "idle"
        threadId = try? c.decode(String.self, forKey: .threadId)
        history = try? c.decode(TranscriptHistoryPage.self, forKey: .history)
        if let d = try? c.decode(Double.self, forKey: .generatedAt) {
            generatedAt = d
        } else if let i = try? c.decode(Int.self, forKey: .generatedAt) {
            generatedAt = Double(i)
        } else {
            generatedAt = Date().timeIntervalSince1970 * 1000
        }
        if let all = try? c.decode([ActivityEntry].self, forKey: .entries) {
            entries = all.filter(Self.isVisible)
        } else if var nested = try? c.nestedUnkeyedContainer(forKey: .entries) {
            var kept: [ActivityEntry] = []
            while !nested.isAtEnd {
                guard let element = try? nested.superDecoder() else { break }
                if let item = try? ActivityEntry(from: element), Self.isVisible(item) {
                    kept.append(item)
                }
            }
            entries = kept
        } else {
            entries = []
        }
    }

    private static func isVisible(_ entry: ActivityEntry) -> Bool {
        !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || entry.kind == "tool" || entry.attachments?.isEmpty == false || entry.images?.isEmpty == false
    }
}
