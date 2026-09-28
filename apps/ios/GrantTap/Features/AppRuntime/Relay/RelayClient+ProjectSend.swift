import Foundation

extension RelayClient {
    func sendProjectCortex(
        _ configuration: CortexIntegrationSet, completion: ((Error?) -> Void)? = nil
    ) {
        guard let body = Self.projectCortexPayload(configuration) else {
            completion?(RelaySendError.encoding)
            return
        }
        sendRaw(body, completion: completion)
    }

    static func projectCortexPayload(
        _ configuration: CortexIntegrationSet,
        now: Double = Date().timeIntervalSince1970 * 1_000,
        operationId: String = UUID().uuidString.lowercased()
    ) -> Data? {
        let payload: [String: Any] = [
            "type": "config.set",
            "cortexIntegration": [
                "projectId": configuration.projectId,
                "enabled": configuration.enabled,
                "maxTokens": configuration.maxTokens,
            ],
            "createdAt": now.rounded(.down),
            "expiresAt": (now + 15 * 60_000).rounded(.down),
            "operationId": operationId,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    func sendProjectCapabilityRequest(_ request: ProjectCapabilityRequest) {
        let payload = ProjectCapabilityRequestSet(
            type: "project.capability.request", sessionId: request.projectId,
            requestId: request.requestId ?? UUID().uuidString.lowercased(), projectId: request.projectId,
            kind: request.kind, name: request.name, source: request.source,
            version: request.version, artifactDigest: request.artifactDigest,
            targetEndpointId: request.targetEndpointId, requestedAt: request.requestedAt
        )
        sendSession(payload: payload, sessionId: request.projectId, ttl: 24 * 60 * 60)
    }

    func sendProjectAutoAccept(
        projectId: String, level: String?, baseRevision: Int? = nil,
        instanceEpoch: String? = nil
    ) {
        guard let body = Self.projectAutoAcceptPayload(
            projectId: projectId, level: level, baseRevision: baseRevision,
            instanceEpoch: instanceEpoch
        ) else { return }
        sendRaw(body)
    }

    static func projectAutoAcceptPayload(
        projectId: String, level: String?, baseRevision: Int? = nil,
        instanceEpoch: String? = nil,
        now: Double = Date().timeIntervalSince1970 * 1_000,
        operationId: String = UUID().uuidString.lowercased()
    ) -> Data? {
        let value: Any = level.map { $0 as Any } ?? NSNull()
        var payload: [String: Any] = [
            "type": "config.set",
            "autoAcceptProject": ["projectId": projectId, "level": value],
            "createdAt": now.rounded(.down),
            "expiresAt": (now + 15 * 60_000).rounded(.down),
            "operationId": operationId,
        ]
        if let baseRevision { payload["baseRevision"] = baseRevision }
        if let instanceEpoch { payload["instanceEpoch"] = instanceEpoch }
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
