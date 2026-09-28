import Foundation

struct ChildThreadDisplayRow: Identifiable {
    let thread: ChildThreadInfo
    let visualDepth: Int

    var id: String { thread.threadId }

    var displayLabel: String {
        if let agentName = nonempty(thread.agentName) { return agentName }
        if let title = nonempty(thread.title) { return title }
        return "Agent \(thread.threadId.prefix(8))"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum ChildThreadTree {
    private static let maximumActivityFallbackThreads = 32

    static func rows(rootId: String, threads: [ChildThreadInfo]) -> [ChildThreadDisplayRow] {
        rows(rootId: rootId, threads: threads, activity: [])
    }

    static func rows(
        rootId: String,
        threads: [ChildThreadInfo],
        activity: [ActivityEntry]
    ) -> [ChildThreadDisplayRow] {
        let candidates = threads.isEmpty
            ? activityFallbackThreads(rootId: rootId, entries: activity)
            : threads
        var byId: [String: ChildThreadInfo] = [:]
        for thread in candidates where thread.threadId != rootId {
            if let previous = byId[thread.threadId],
               previous.lastActivityAt > thread.lastActivityAt { continue }
            byId[thread.threadId] = thread
        }

        var childrenByParent: [String: [ChildThreadInfo]] = [:]
        for thread in byId.values {
            childrenByParent[thread.parentThreadId, default: []].append(thread)
        }
        for parent in childrenByParent.keys {
            childrenByParent[parent]?.sort(by: newestFirst)
        }

        var result: [ChildThreadDisplayRow] = []
        var emitted: Set<String> = []
        func appendChildren(of parentId: String, depth: Int) {
            for thread in childrenByParent[parentId] ?? [] where !emitted.contains(thread.threadId) {
                emitted.insert(thread.threadId)
                result.append(ChildThreadDisplayRow(thread: thread, visualDepth: depth))
                appendChildren(of: thread.threadId, depth: depth + 1)
            }
        }
        appendChildren(of: rootId, depth: 1)
        return result
    }

    private static func activityFallbackThreads(
        rootId: String,
        entries: [ActivityEntry]
    ) -> [ChildThreadInfo] {
        struct Summary {
            var title: String?
            var startedAt: Double
            var lastActivityAt: Double
            var tokens: Int
        }

        var summaries: [String: Summary] = [:]
        for entry in entries {
            guard let id = entry.childThreadId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  (entry.childThreadDepth ?? 1) <= 1 else { continue }
            let tokens = max(0, entry.estimatedContextTokens ?? 0)
            if var summary = summaries[id] {
                summary.startedAt = min(summary.startedAt, entry.createdAt)
                if entry.createdAt >= summary.lastActivityAt {
                    summary.lastActivityAt = entry.createdAt
                    if let title = nonempty(entry.childThreadTitle) { summary.title = title }
                }
                summary.tokens = addingWithoutOverflow(summary.tokens, tokens)
                summaries[id] = summary
            } else {
                summaries[id] = Summary(
                    title: nonempty(entry.childThreadTitle),
                    startedAt: entry.createdAt,
                    lastActivityAt: entry.createdAt,
                    tokens: tokens
                )
            }
        }

        return summaries
            .sorted {
                $0.value.lastActivityAt == $1.value.lastActivityAt
                    ? $0.key < $1.key
                    : $0.value.lastActivityAt > $1.value.lastActivityAt
            }
            .prefix(maximumActivityFallbackThreads)
            .map { id, summary in
                ChildThreadInfo(
                    threadId: id,
                    parentThreadId: rootId,
                    title: summary.title,
                    depth: 1,
                    state: "idle",
                    startedAt: summary.startedAt,
                    lastActivityAt: summary.lastActivityAt,
                    tokensSession: summary.tokens,
                    tokensLastTurn: summary.tokens
                )
            }
    }

    private static func newestFirst(_ lhs: ChildThreadInfo, _ rhs: ChildThreadInfo) -> Bool {
        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        return lhs.threadId < rhs.threadId
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
