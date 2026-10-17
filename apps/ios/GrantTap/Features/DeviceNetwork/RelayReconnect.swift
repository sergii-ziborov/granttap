import Foundation

extension RelayClient {
    func cancelScheduledReconnect() {
        reconnectGeneration = nil
        reconnectScheduled = false
    }

    /// Only the current disconnected generation may reopen transport. A delayed
    /// retry must not tear down a socket recovered by foregrounding or routing.
    func scheduleReconnect() {
        guard wantsConnection, task == nil, !reconnectScheduled else { return }
        let generation = UUID()
        reconnectGeneration = generation
        reconnectScheduled = true
        let delay = retryDelay
        retryDelay = RelayReconnectBackoff.nextDelay(after: delay, cap: maxRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reconnectGeneration == generation else { return }
            self.cancelScheduledReconnect()
            guard self.wantsConnection, self.task == nil else { return }
            self.openSocket()
        }
    }

    func noteSocketOpened(now: TimeInterval = Date().timeIntervalSince1970) {
        socketOpenedAt = now
    }

    /// Only a connection that stayed up earns a quick reconnect; one the relay
    /// refused right after it opened must not be reopened every second.
    func noteSocketClosed(closeCode: Int, reason: Data? = nil, now: TimeInterval = Date().timeIntervalSince1970) {
        retryDelay = RelayReconnectBackoff.delayAfterClose(
            current: retryDelay, openFor: socketOpenedAt.map { now - $0 }, closeCode: closeCode,
            reason: reason.flatMap { String(data: $0, encoding: .utf8) }
        )
        socketOpenedAt = nil
    }
}

enum RelayReconnectBackoff {
    /// A connection that lived this long was healthy; its successor may retry quickly.
    static let healthyLifetime: TimeInterval = 30
    /// A policy refusal (WebSocket 1008) will be refused again; ask again rarely.
    static let policyDelay: TimeInterval = 60

    /// 1008 and the relay's 44xx closes are policy refusals: admission, cool-down, rate limit.
    static func delayAfterClose(current: TimeInterval, openFor: TimeInterval?, closeCode: Int,
                                reason: String? = nil) -> TimeInterval {
        if closeCode == 1008 || (4400...4499).contains(closeCode) {
            return max(current, policyDelay, reason.flatMap(retryAfter) ?? 0)
        }
        if let openFor, openFor >= healthyLifetime { return 1 }
        return current
    }

    /// The relay's close reason may carry `; retry-after=<seconds>`.
    static func retryAfter(_ reason: String) -> TimeInterval? {
        guard let range = reason.range(of: #"retry-after=(\d{1,5})"#, options: .regularExpression) else { return nil }
        return TimeInterval(reason[range].dropFirst("retry-after=".count))
    }

    /// Doubling stops at the ordinary cap, but never shortens a longer policy wait.
    static func nextDelay(after delay: TimeInterval, cap: TimeInterval) -> TimeInterval {
        delay > cap ? delay : min(cap, delay * 2)
    }
}
