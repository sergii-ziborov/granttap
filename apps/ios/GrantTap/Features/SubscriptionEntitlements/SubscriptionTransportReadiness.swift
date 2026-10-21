import Foundation

@MainActor
extension SubscriptionStore {
    /// Valid current evidence opens the route immediately. Revalidation is single-flight in the background.
    func connectionTransportAccess() async -> Bool {
        if allowsManagedTransport {
            revalidateTransportInBackground()
            return true
        }
        if let pending = transportReadiness { return await pending.value }
        let pending = Task { @MainActor [weak self] in
            guard let self else { return false }
            let stream = AsyncStream<Bool>.makeStream()
            let account = Task { @MainActor in
                await self.refreshAccountTransportAccess()
                stream.continuation.yield(self.allowsManagedTransport)
            }
            let distribution = Task { @MainActor in
                if await self.betaEnvironmentLoader() { self.betaRelayAccess = true }
                stream.continuation.yield(self.allowsManagedTransport)
            }
            defer { stream.continuation.finish(); account.cancel(); distribution.cancel() }
            var replies = 0
            for await allowed in stream.stream {
                if allowed { return true }
                replies += 1
                if replies == 2 { break }
            }
            await self.refresh()
            return self.allowsManagedTransport
        }
        transportReadiness = pending
        let allowed = await pending.value
        transportReadiness = nil
        return allowed
    }

    private func revalidateTransportInBackground() {
        guard transportRevalidation == nil else { return }
        transportRevalidation = Task { @MainActor [weak self] in
            await self?.recheckTransportIfNeeded()
            self?.transportRevalidation = nil
        }
    }
}
