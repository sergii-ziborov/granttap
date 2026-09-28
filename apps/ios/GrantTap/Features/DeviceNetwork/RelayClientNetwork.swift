import Foundation

extension RelayClient {
    func openSocket() {
        guard wantsConnection else { return }
        #if DEBUG
        // Existing development pairings retain normal live behavior, never demo.
        if pairing.directoryUrl == nil {
            openResolvedSocket(pairing.relayUrl)
            return
        }
        #endif
        endpointLookup?.cancel()
        endpointLookup = Task { @MainActor [weak self] in
            guard let self else { return }
            await resolveNetworkRoute(reconnect: true)
        }
    }

    @MainActor func resolveNetworkRoute(reconnect: Bool) async {
        let address = await DeviceEndpointDirectory.resolve(pairing: pairing,
            allowsManaged: SubscriptionStore.shared.entitlement.state.allowsRemoteInfrastructure)
        guard !Task.isCancelled, wantsConnection else { return }
        guard let address else {
            interruptSocketForReplacement()
            onConnectionChange?(false)
            scheduleReconnect()
            return
        }
        if reconnect || address != resolvedRelayURL || task == nil { openResolvedSocket(address) }
    }

    func startEndpointPolling() {
        guard endpointPolling == nil else { return }
        #if DEBUG
        guard pairing.directoryUrl != nil else { return }
        #endif
        endpointPolling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self, self.wantsConnection else { return }
                await self.resolveNetworkRoute(reconnect: false)
            }
        }
    }
}
