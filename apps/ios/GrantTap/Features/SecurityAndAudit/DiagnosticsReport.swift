import Foundation

/// What a bug report may say about this device.
///
/// GrantTap collects nothing and ships no analytics, and a report that quietly
/// uploaded state would make that untrue. So the report is built here, shown in
/// full before it is sent, and sent by the person rather than by the app.
///
/// Nothing identifying and nothing secret goes in: no pairing keys, no APNs
/// token, no room ids, no chat content, no command text. What is left is the
/// shape of the install, which is what a report actually needs.
struct DiagnosticsReport: Equatable {
    let appVersion: String
    let build: String
    let systemVersion: String
    let deviceModel: String
    let locale: String
    let linkedComputers: Int
    let connection: String
    let liveSessions: Int
    let governedProjects: Int

    var text: String {
        [
            "GrantTap \(appVersion) (\(build))",
            "iOS \(systemVersion) · \(deviceModel) · \(locale)",
            "Linked computers: \(linkedComputers)",
            "Connection: \(connection)",
            "Live tasks: \(liveSessions)",
            "Projects reporting policy: \(governedProjects)",
        ].joined(separator: "\n")
    }

    /// Redaction is asserted, not assumed: anything resembling a secret in the
    /// finished text is a defect, so the shape is checked where it is built.
    static func containsSecret(_ text: String) -> Bool {
        let lowered = text.lowercased()
        for marker in ["key", "token", "secret", "password", "room", "bearer"]
        where lowered.contains(marker) {
            return true
        }
        // A base64-ish run long enough to be key material has no business here.
        return text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.count >= 32 }
    }
}
