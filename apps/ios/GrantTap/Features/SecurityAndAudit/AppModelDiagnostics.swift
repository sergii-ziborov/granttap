import Foundation
import UIKit

extension AppModel {
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
            governedProjects: projectGovernance.count
        )
    }
}
