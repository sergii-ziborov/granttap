import Foundation

/// The id a transcript row is actually registered under.
///
/// The chat scrolls by id, and an id that matches nothing scrolls nowhere in
/// silence — which is how both "jump to this call" and the ordinary scroll to
/// the newest line could look like they had simply chosen not to move.
///
/// Root rows come from the combined timeline and carry its prefix. A row inside
/// an agent's own conversation is registered under the bare entry id, and the
/// conversation itself under a thread id, because that is the row the reader is
/// actually being sent to.
enum ChatScrollTarget {
    /// During backfill keep the last user line. After the agent writes, follow the foot.
    static func followTarget(_ items: [CombinedTaskTimelineItem]) -> String? {
        guard let lastUser = items.last(where: {
            if case .activity(let entry) = $0 { return entry.kind == "user" }
            return false
        }) else { return items.last?.id }
        if items.contains(where: { $0.createdAt > lastUser.createdAt + 400 }) {
            return items.last?.id
        }
        return lastUser.id
    }

    static func forEntry(_ entry: ActivityEntry) -> String {
        if let thread = entry.childThreadId { return "thread:\(thread)" }
        return "activity:\(entry.id)"
    }
}
