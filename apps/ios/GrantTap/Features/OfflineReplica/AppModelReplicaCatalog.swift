import Foundation

@MainActor
extension AppModel {
    /// Restore only durable local state; this must not await transport access.
    func restoreLocalReplica() {
        guard !demoMode else { return }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["GRANTTAP_DEMO"] != "1",
              environment["GRANTTAP_TEST_CONNECTION_LIST"] != "1",
              environment["GRANTTAP_TEST_INVITE_SCOPES"] == nil else { return }
        #endif
        ReplicaImageStore.shared.prune()
        loadConnectionRegistry()
        loadCachedSessionCatalogIfNeeded()
    }

    func loadReplicaCatalogIndex() {
        guard !demoMode, let saved = SessionCatalogCache.load() else { return }
        let rows = Self.filterRealCatalogSessions(saved.sessions + saved.history, allowDemo: false)
            .filter(isReplicaSessionVisible)
        replicaSessionIndex = Dictionary(rows.map { ($0.sessionId, $0) },
                                         uniquingKeysWith: { first, _ in first })
    }
}
