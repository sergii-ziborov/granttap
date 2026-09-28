import Foundation

enum ProviderHookReviewProgress: Equatable {
    case pending(request: ProviderHookTrust, room: String)
    case finished(ProviderHookTrustResult)
    case unavailable
}

extension AppModel {
    static func hookReviewKey(room: String, event: String) -> String { "\(room)\u{1f}\(event)" }

    @discardableResult
    func reviewProviderHook(_ hook: ProviderHookInfo, room: String, endpointId: String,
                            send: ((ProviderHookTrust) -> Void)? = nil) -> Bool {
        guard hook.canReview, let key = hook.key, let hash = hook.currentHash, !endpointId.isEmpty else {
            return false
        }
        if send == nil && !canReviewHooks(in: room) { return false }
        let request = ProviderHookTrust(type: "provider.hook.trust", agent: "codex",
            endpointId: endpointId, event: hook.event, key: key, currentHash: hash,
            requestId: UUID().uuidString, createdAt: Date().timeIntervalSince1970 * 1_000)
        let reviewKey = Self.hookReviewKey(room: room, event: hook.event)
        if case .pending = providerHookReviews[reviewKey] { return false }
        providerHookReviews[reviewKey] = .pending(request: request, room: room)
        if let send {
            send(request)
        } else {
            #if targetEnvironment(macCatalyst)
            if room == "local-mac", let reader = localMCPReader {
                Task { await trustLocalHook(request, reader: reader, room: room) }
            } else {
                relaysByRoom[room]?.send(payload: request, ttl: 5 * 60)
            }
            #else
            relaysByRoom[room]?.send(payload: request, ttl: 5 * 60)
            #endif
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, case .pending(let current, _) = self.providerHookReviews[reviewKey],
                  current.requestId == request.requestId else { return }
            self.providerHookReviews[reviewKey] = .unavailable
        }
        return true
    }

    func receive(_ result: ProviderHookTrustResult, fromRoom room: String) {
        guard result.agent == "codex", result.type == "provider.hook.trust.result",
              result.hooks.count <= 2, Set(result.hooks.map(\.event)).count == result.hooks.count,
              result.checkedAt.isFinite, result.message.count <= 512 else { return }
        let match = providerHookReviews.first { _, progress in
            guard case .pending(let request, let source) = progress else { return false }
            return source == room && request.requestId == result.requestId &&
                request.endpointId == result.endpointId
        }
        guard let match, case .pending(let request, _) = match.value else { return }
        if result.ok {
            guard let applied = result.hooks.first(where: { $0.event == request.event }),
                  applied.key == request.key, applied.currentHash == request.currentHash,
                  applied.isActive, applied.canReview else { return }
        }
        providerHookReviews[match.key] = .finished(result)
        if let index = agentIntegrationsByRoom[room]?.firstIndex(where: { $0.agent == "codex" }) {
            agentIntegrationsByRoom[room]?[index].hooks = result.hooks
            agentIntegrationsByRoom[room]?[index].hooksCheckedAt = result.checkedAt
        }
    }

    private func canReviewHooks(in room: String) -> Bool {
        #if targetEnvironment(macCatalyst)
        if room == "local-mac" { return localMCPReader?.status?.desktopEngineSocket != nil }
        #endif
        return relaysByRoom[room] != nil
    }

    #if targetEnvironment(macCatalyst)
    private func trustLocalHook(_ request: ProviderHookTrust, reader: MacLocalMCPModel, room: String) async {
        do {
            let result = try await reader.trustHook(request)
            receive(result, fromRoom: room)
            await reader.refresh()
        } catch {
            providerHookReviews[Self.hookReviewKey(room: room, event: request.event)] = .unavailable
        }
    }
    #endif
}
