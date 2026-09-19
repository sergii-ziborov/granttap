import CryptoKit
import Foundation

enum ConfigCommandContext {
    static func signed(
        enabled: Bool? = nil,
        excludeSession: String? = nil,
        includeSession: String? = nil,
        autoAcceptDefault: String? = nil,
        autoAcceptSession: AutoAcceptSessionSet? = nil,
        autoAcceptProject: AutoAcceptProjectSet? = nil,
        autoAcceptPaused: Bool? = nil,
        provider: String? = nil,
        providerEnabled: Bool? = nil,
        meshEnabled: Bool? = nil,
        baseRevision: Int? = nil,
        instanceEpoch: String? = nil
    ) -> ConfigSet {
        let createdAt = Date().timeIntervalSince1970 * 1000
        var payload = ConfigSet(
            type: "config.set",
            enabled: enabled,
            excludeSession: excludeSession,
            includeSession: includeSession,
            autoAcceptDefault: autoAcceptDefault,
            autoAcceptSession: autoAcceptSession,
            autoAcceptProject: autoAcceptProject,
            autoAcceptPaused: autoAcceptPaused,
            provider: provider,
            providerEnabled: providerEnabled,
            meshEnabled: meshEnabled,
            createdAt: createdAt
        )
        payload.operationId = UUID().uuidString.lowercased()
        payload.baseRevision = baseRevision
        payload.expiresAt = createdAt + 120_000
        payload.payloadDigest = digest(payload)
        payload.instanceEpoch = instanceEpoch
        return payload
    }

    /// Same field order as the Mac `configMutationDigest`.
    static func digest(_ message: ConfigSet) -> String {
        let session: String
        if let item = message.autoAcceptSession {
            let level = item.level.map(jsonString) ?? "null"
            session = "{\"sessionId\":\(jsonString(item.sessionId)),\"level\":\(level)}"
        } else {
            session = "null"
        }
        let project: String
        if let item = message.autoAcceptProject {
            let level = item.level.map(jsonString) ?? "null"
            project = "{\"projectId\":\(jsonString(item.projectId)),\"level\":\(level)}"
        } else {
            project = "null"
        }
        let body = "{"
            + "\"enabled\":\(jsonBool(message.enabled)),"
            + "\"excludeSession\":\(jsonOptionalString(message.excludeSession)),"
            + "\"includeSession\":\(jsonOptionalString(message.includeSession)),"
            + "\"autoAcceptDefault\":\(jsonOptionalString(message.autoAcceptDefault)),"
            + "\"autoAcceptSession\":\(session),"
            + "\"autoAcceptProject\":\(project),"
            + "\"autoAcceptPaused\":\(jsonBool(message.autoAcceptPaused)),"
            + "\"provider\":\(jsonOptionalString(message.provider)),"
            + "\"providerEnabled\":\(jsonBool(message.providerEnabled)),"
            + "\"meshEnabled\":\(jsonBool(message.meshEnabled)),"
            + "\"contextCompilerEnabled\":null"
            + "}"
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonBool(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? "null"
    }

    private static func jsonOptionalString(_ value: String?) -> String {
        value.map(jsonString) ?? "null"
    }

    private static func jsonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
