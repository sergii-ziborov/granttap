import Foundation

/// Immutable snapshots are encoded and written off the interface thread.
/// Pending refreshes of the same chat coalesce; different chats never replace one another.
final class TranscriptArchiveWriter {
    private let queue = DispatchQueue(label: "com.ziborov.granttap.transcript-archive", qos: .utility)
    private let lock = NSLock()
    private var pending: [String: SessionActivity] = [:]
    private let write: (SessionActivity) -> Void

    init(write: @escaping (SessionActivity) -> Void) { self.write = write }

    func enqueue(_ activities: [String: SessionActivity]) {
        lock.lock()
        pending.merge(activities) { _, latest in latest }
        // A finite batch keeps read/clear/background-completion barriers fair,
        // even if the computer continues streaming new activity.
        queue.async { self.drain() }
        lock.unlock()
    }

    /// Loading and explicit cleanup require a consistent durable state.
    func barrier<T>(_ action: () throws -> T) rethrows -> T {
        try queue.sync(execute: action)
    }

    func finish(_ completion: @escaping () -> Void) {
        queue.async(execute: completion)
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending = [:]
        lock.unlock()
        for activity in batch.values { write(activity) }
    }
}
