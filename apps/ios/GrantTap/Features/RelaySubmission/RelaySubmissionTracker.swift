import Foundation

enum RelaySubmissionFailure: Error, Equatable { case notConfirmed, disconnected, rejected, capacity }

/// Tracks relay persistence separately from native execution receipts.
final class RelaySubmissionTracker {
    typealias Completion = (Error?) -> Void
    private let limit: Int
    private let lock = NSLock()
    private var pending: [String: [UUID: Completion]] = [:]

    init(limit: Int = 256) { self.limit = max(0, limit) }

    func register(_ id: String, completion: @escaping Completion) -> UUID? {
        lock.lock()
        guard pending.values.reduce(0, { $0 + $1.count }) < limit else {
            lock.unlock()
            completion(RelaySubmissionFailure.capacity)
            return nil
        }
        let token = UUID()
        pending[id, default: [:]][token] = completion
        lock.unlock()
        return token
    }

    @discardableResult
    func complete(_ id: String, error: Error? = nil) -> Bool {
        lock.lock()
        let completions = pending.removeValue(forKey: id).map { Array($0.values) } ?? []
        lock.unlock()
        for completion in completions { completion(error) }
        return !completions.isEmpty
    }

    func expire(_ id: String, token: UUID) {
        lock.lock()
        let completion = pending[id]?.removeValue(forKey: token)
        if pending[id]?.isEmpty == true { pending.removeValue(forKey: id) }
        lock.unlock()
        completion?(RelaySubmissionFailure.notConfirmed)
    }

    func disconnect() {
        lock.lock()
        let completions = pending.values.flatMap { $0.values }
        pending.removeAll()
        lock.unlock()
        for completion in completions { completion(RelaySubmissionFailure.disconnected) }
    }
}
