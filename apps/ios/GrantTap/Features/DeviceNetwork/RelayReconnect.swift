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
        retryDelay = min(maxRetryDelay, retryDelay * 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reconnectGeneration == generation else { return }
            self.cancelScheduledReconnect()
            guard self.wantsConnection, self.task == nil else { return }
            self.openSocket()
        }
    }
}
