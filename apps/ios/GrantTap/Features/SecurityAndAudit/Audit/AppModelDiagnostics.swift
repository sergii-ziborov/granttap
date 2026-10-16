import Foundation
import UIKit
import CryptoKit

extension AppModel {
    #if DEBUG
    var nowReplicaTestStatus: String {
        guard !sessions.isEmpty, isMacCatalogFresh else { return "waiting" }
        return sessions.allSatisfy { session in
            guard let saved = activities[session.sessionId], saved.history != nil else { return false }
            return saved.generatedAt >= session.lastActivityAt
        } ? "ready" : "waiting"
    }
    #endif

    /// The shape of this install, with nothing identifying or secret in it.
    func diagnosticsReport() -> DiagnosticsReport {
        let bundle = Bundle.main.infoDictionary
        return DiagnosticsReport(
            appVersion: bundle?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: bundle?["CFBundleVersion"] as? String ?? "unknown",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            locale: Locale.current.identifier,
            linkedComputers: connectionRegistry.connections.count,
            connection: connectionSnapshot.statusTitle,
            liveSessions: sessions.count,
            governedProjects: projectGovernance.count,
            providerCounts: Dictionary(grouping: sessions, by: \.agent)
                .map { "\($0.key):\($0.value.count)" }.sorted().joined(separator: ", "),
            transportAllowed: SubscriptionStore.shared.allowsManagedTransport,
            recoveryFailed: accountSpaceSyncError != nil,
            routes: connectionRegistry.connections.map { connection in
                let pairing = connection.pairing
                func fingerprint(_ value: String) -> String {
                    SHA256.hash(data: Data(value.utf8)).prefix(6)
                        .map { String(format: "%02x", $0) }.joined()
                }
                return "Route \(fingerprint(connection.id)): \(snapshotForConnection(connection).statusTitle)"
                    + " · catalog \(String(format: "%.0f", connection.lastCatalogAt))"
                    + " · controller \(fingerprint(pairing.myPublicKey))"
                    + " · publisher \(fingerprint(pairing.peerPublicKey))"
            }
        )
    }

    func saveRequestedDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_DIAGNOSTICS"] == "1" else { return }
        let text = diagnosticsReport().text
            + "\nCaptured at: \(Date().timeIntervalSince1970)"
            + "\nAccount session saved: \(GrantTapAccountAPI.session != nil)"
            + "\nVisible computer routes: \(connectionOverview.count)"
            + "\nOverview requested: \(log.contains("Opened computer connection overview"))"
            + "\nCached Now chats: \(sessions.filter { activities[$0.sessionId] != nil }.count)/\(sessions.count)"
            + "\nHistory requests pending: \(transcriptBackfill.pending.count)"
            + "\nWire counters: \(relaysByRoom.values.map { $0.wireDiagnosticCounts.description }.sorted())"
        guard !DiagnosticsReport.containsSecret(text) else { return }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? text.write(to: root.appendingPathComponent("GrantTapConnectionDiagnostics.txt"),
                        atomically: true, encoding: .utf8)
        #endif
    }
}
