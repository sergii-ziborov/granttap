import Foundation

/// A fair, bounded transport queue. Storage has no row or chat eviction limit.
struct TranscriptBackfill {
    struct Request: Equatable {
        let sessionId: String
        let cursor: String?
        let sentAt: Double
        var revision: Double? = nil
    }

    private(set) var pending: [String: Request] = [:]
    private var retryAt: [String: Double] = [:]
    private var headVersions: [String: Double] = [:]
    private var headRequestedAt: [String: Double] = [:]
    private var lastServed: [String: Double] = [:]
    var concurrency = 2
    static let liveHeadIntervalMs = 30_000.0

    mutating func next(activeIds: Set<String>, activities: [String: SessionActivity],
                       available: Set<String>, versions: [String: Double] = [:], now: Double) -> [Request] {
        headVersions = headVersions.filter { activeIds.contains($0.key) }
        headRequestedAt = headRequestedAt.filter { activeIds.contains($0.key) }
        for (id, request) in pending where !activeIds.contains(id) || now - request.sentAt >= 20_000 {
            pending.removeValue(forKey: id)
            retryAt[id] = now + 30_000
        }
        let candidates = activeIds.intersection(available).filter { id in
            pending[id] == nil && (retryAt[id] ?? 0) <= now
                && (activities[id]?.history?.hasMore != false
                    || refreshHead(id, history: activities[id]?.history, version: versions[id], now: now))
        }.sorted { left, right in
            let leftHead = refreshHead(left, history: activities[left]?.history, version: versions[left], now: now)
            let rightHead = refreshHead(right, history: activities[right]?.history, version: versions[right], now: now)
            if leftHead != rightHead { return leftHead }
            let l = lastServed[left] ?? 0, r = lastServed[right] ?? 0
            if l != r { return l < r }
            if versions[left] != versions[right] { return (versions[left] ?? 0) > (versions[right] ?? 0) }
            return left < right
        }
        let requests = candidates.prefix(max(0, concurrency - pending.count)).map { id in
            Request(sessionId: id,
                cursor: refreshHead(id, history: activities[id]?.history, version: versions[id], now: now)
                    ? nil : activities[id]?.history?.cursor,
                sentAt: now, revision: versions[id])
        }
        for request in requests {
            pending[request.sessionId] = request
            lastServed[request.sessionId] = now
            if request.cursor == nil { headRequestedAt[request.sessionId] = now }
        }
        return requests
    }

    private func refreshHead(_ id: String, history: TranscriptHistoryPage?, version: Double?, now: Double) -> Bool {
        guard let version else { return false }
        if headVersions[id] == nil { return true }
        guard headVersions[id] != version else { return false }
        // Fresh Now content must not wait behind a large historical transcript.
        // Bound refresh frequency while older pages remain, so both make progress.
        return history?.hasMore == false
            || now - (headRequestedAt[id] ?? 0) >= Self.liveHeadIntervalMs
    }

    mutating func received(_ activity: SessionActivity, now: Double) {
        guard let request = pending[activity.sessionId], let history = activity.history,
              history.requestedCursor == request.cursor else { return }
        pending.removeValue(forKey: activity.sessionId)
        if request.cursor == nil, let revision = request.revision {
            headVersions[activity.sessionId] = revision
        }
        if history.hasMore && (history.cursor == nil || history.cursor == request.cursor) {
            // Broken/expired cursors must not spin or advertise completion.
            headVersions.removeValue(forKey: activity.sessionId)
            retryAt[activity.sessionId] = now + 60_000
        }
    }

    mutating func failed(_ request: Request, now: Double) {
        guard pending[request.sessionId] == request else { return }
        pending.removeValue(forKey: request.sessionId)
        retryAt[request.sessionId] = now + 30_000
    }
}
