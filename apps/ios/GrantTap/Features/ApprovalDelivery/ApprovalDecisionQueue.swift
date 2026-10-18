import Foundation

/// Explicit decisions survive transport loss, scoped to the original request.
/// Relay storage and native application are independent acknowledgements.
final class ApprovalDecisionQueue {
    struct Entry: Codable, Equatable {
        let requestId: String
        let roomId: String
        let sessionId: String?
        let decision: String
        let by: String
        let createdAt: Double
        var sentAt: Double? = nil
        var relayStoredAt: Double? = nil
        var note: String? = nil
    }

    private let url: URL
    private(set) var entries: [Entry]
    private var submissions: Set<String> = []
    private var retryCounts: [String: Int] = [:]

    func beginSubmission(_ entry: Entry, now: Double = Date().timeIntervalSince1970) -> Bool {
        guard entry.relayStoredAt == nil, entry.createdAt.isFinite,
              now >= entry.createdAt, now - entry.createdAt < 15 * 60 else { return false }
        return submissions.insert(entry.requestId).inserted
    }

    func finishSubmission(_ requestId: String, succeeded: Bool) -> TimeInterval {
        submissions.remove(requestId)
        if succeeded { retryCounts.removeValue(forKey: requestId); return 0 }
        let attempt = retryCounts[requestId, default: 0]
        retryCounts[requestId] = min(attempt + 1, 3)
        return [2.0, 5, 15, 30][min(attempt, 3)]
    }

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap/approval-decisions.json")
        if let data = try? Data(contentsOf: self.url), data.count <= 256_000,
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved.filter { ["allow", "deny"].contains($0.decision) && !$0.roomId.isEmpty }
        } else { entries = [] }
    }

    func entry(_ requestId: String, roomId: String, sessionId: String?) -> Entry? {
        entries.first { $0.requestId == requestId && $0.roomId == roomId && $0.sessionId == sessionId }
    }

    @discardableResult
    func enqueue(_ entry: Entry) -> Bool {
        guard ["allow", "deny"].contains(entry.decision), !entry.roomId.isEmpty else { return false }
        if let old = entries.first(where: { $0.requestId == entry.requestId }) { return old == entry }
        guard entries.count < 128 else { return false }
        return persist(entries + [entry])
    }

    func markSent(_ entry: Entry, at time: Double?) {
        var next = entries
        guard let index = next.firstIndex(where: {
            $0.requestId == entry.requestId && $0.roomId == entry.roomId && $0.sessionId == entry.sessionId
        }) else { return }
        next[index].sentAt = time
        _ = persist(next)
    }

    func markStored(_ entry: Entry, at time: Double) {
        var next = entries
        guard let index = next.firstIndex(where: {
            $0.requestId == entry.requestId && $0.roomId == entry.roomId && $0.sessionId == entry.sessionId
        }) else { return }
        next[index].relayStoredAt = time
        _ = persist(next)
    }

    func remove(_ requestId: String, roomId: String, sessionId: String?) {
        _ = persist(entries.filter {
            !($0.requestId == requestId && $0.roomId == roomId && $0.sessionId == sessionId)
        })
    }

    func removeRoom(_ roomId: String) { _ = persist(entries.filter { $0.roomId != roomId }) }

    private func persist(_ next: [Entry]) -> Bool {
        guard let data = try? JSONEncoder().encode(next), data.count <= 256_000 else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            entries = next
            return true
        } catch { return false }
    }
}
