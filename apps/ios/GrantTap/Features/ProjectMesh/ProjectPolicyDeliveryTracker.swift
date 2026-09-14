import Foundation

final class ProjectPolicyDeliveryTracker {
    private let lock = NSLock()
    private var remaining: Int
    private var delivered = false

    init(count: Int) {
        remaining = max(0, count)
    }

    /// Returns true once, only when every target has failed.
    func resolve(error: Error?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        if error == nil { delivered = true }
        return remaining == 0 && !delivered
    }
}
