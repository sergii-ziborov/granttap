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
    static func forEntry(_ entry: ActivityEntry) -> String {
        if let thread = entry.childThreadId { return "thread:\(thread)" }
        return "activity:\(entry.id)"
    }
}
