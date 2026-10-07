import Foundation

enum ProjectMeshWireValidator {
    private static let eventKeys: Set<String> = [
        "type", "sessionId", "eventId", "projectId", "taskId", "sourceSessionId",
        "sourceActorId", "targetSessionId", "eventType", "createdAt", "expiresAt", "payload",
    ]
    private static let payloadKeys: Set<String> = [
        "summary", "dependsOnTaskId", "question", "category", "questionEventId", "answer",
        "capsule", "receipt", "reason", "claim", "claimId", "resource", "artifact",
        "commitSha", "otherOwnerSessionId", "resolved", "needsUser", "failed",
    ]
    private static let capsuleKeys: Set<String> = [
        "taskId", "goal", "currentStatus", "sourceProvider", "sourceActorId", "sourceComputer",
        "targetProvider", "targetActorId", "targetComputer", "targetModel", "userComment",
        "repository", "baseSha", "branch",
        "latestCommit", "dirtyDiffHash", "workingTree", "filesChanged", "testsStatus",
        "dependencies", "resourceClaims", "remainingWork", "importantDecisions", "checkpoint", "createdAt",
    ]
    private static let checkpointKeys: Set<String> = ["status", "files", "excluded"]
    private static let workingTreeStates: Set<String> = ["clean", "dirty", "unknown"]
    private static let providers: Set<String> = ["claude", "codex", "cursor", "grok", "grok_bot"]

    static func validEvent(_ data: Data) -> Bool {
        guard data.count <= 64 * 1_024,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(event.keys).isSubset(of: eventKeys),
              event["type"] as? String == "mesh.event",
              let sessionId = boundedString(event["sessionId"], max: 128),
              let taskId = boundedString(event["taskId"], max: 128),
              sessionId == taskId,
              boundedString(event["eventId"], max: 128) != nil,
              boundedString(event["projectId"], max: 128) != nil,
              boundedString(event["sourceSessionId"], max: 128) != nil,
              let payload = event["payload"] as? [String: Any],
              Set(payload.keys).isSubset(of: payloadKeys)
        else { return false }
        if event["targetSessionId"] != nil,
           boundedString(event["targetSessionId"], max: 128) == nil { return false }
        if event["sourceActorId"] != nil,
           boundedString(event["sourceActorId"], max: 128) == nil { return false }
        return validPayload(payload)
    }

    static func validSnapshot(_ data: Data) -> Bool {
        let allowed: Set<String> = [
            "type", "sessionId", "projectId", "publisherEndpointId",
            "project", "tasks", "executions",
            "bindings", "peers", "claims", "dependencies", "events", "generatedAt",
            "skills", "incomplete", "execution", "restrictions", "environment", "modelCatalog",
            "mcpServers", "capabilityRequests", "capabilityObservations",
            "backbone", "repositoryGraphs", "cortex", "knowledge", "supersededKnowledgeRecordIds",
        ]
        guard data.count <= 256 * 1_024,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys).isSubset(of: allowed),
              value["type"] as? String == "mesh.snapshot",
              let sessionId = boundedString(value["sessionId"], max: 128),
              sessionId == boundedString(value["projectId"], max: 128),
              validBindings(value["bindings"], projectId: sessionId),
              validPeers(value["peers"], projectId: sessionId),
              let tasks = value["tasks"] as? [Any], tasks.count <= 64,
              let executions = value["executions"] as? [Any], executions.count <= 128,
              let claims = value["claims"] as? [Any], claims.count <= 128,
              let dependencies = value["dependencies"] as? [Any], dependencies.count <= 128,
              let events = value["events"] as? [Any], events.count <= 128
        else { return false }
        guard let snapshot = try? JSONDecoder().decode(ProjectMeshSnapshot.self, from: data),
              validDecodedSnapshot(snapshot, projectId: sessionId)
        else { return false }
        return events.allSatisfy { event in
            guard JSONSerialization.isValidJSONObject(event),
                  let encoded = try? JSONSerialization.data(withJSONObject: event) else { return false }
            return validEvent(encoded)
        }
    }

    private static func validDecodedSnapshot(_ snapshot: ProjectMeshSnapshot, projectId sessionId: String) -> Bool {
        guard snapshot.publisherEndpointId == nil
                  || boundedString(snapshot.publisherEndpointId, max: 128) != nil,
              (snapshot.skills?.count ?? 0) <= 64,
              snapshot.publisherEndpointId == nil || snapshot.skills?.allSatisfy({
                  $0.endpointId == snapshot.publisherEndpointId
              }) != false,
              (snapshot.mcpServers?.count ?? 0) <= 128,
              snapshot.publisherEndpointId == nil || snapshot.mcpServers?.allSatisfy({
                  $0.endpointId == snapshot.publisherEndpointId
              }) != false,
              Set((snapshot.mcpServers ?? []).map(\.id)).count == (snapshot.mcpServers?.count ?? 0),
              snapshot.mcpServers?.allSatisfy({
                  !$0.name.isEmpty && $0.name.count <= 160
                      && !$0.endpointId.isEmpty && $0.endpointId.count <= 128
                      && $0.sessionIds.count <= 64
                      && Set($0.sessionIds).count == $0.sessionIds.count
                      && ($0.configDigest.map(Self.validDigest) ?? true)
              }) ?? true,
              (snapshot.capabilityRequests?.count ?? 0) <= 128,
              snapshot.capabilityRequests?.allSatisfy({
                  $0.projectId == sessionId && !$0.name.isEmpty && $0.name.count <= 160
                      && ($0.requestId?.count ?? 0) <= 128
                      && ($0.artifactDigest.map(Self.validDigest) ?? true)
              }) != false,
              Set((snapshot.capabilityRequests ?? []).map(\.id)).count
                  == (snapshot.capabilityRequests?.count ?? 0),
              (snapshot.capabilityObservations?.count ?? 0) <= 128,
              snapshot.publisherEndpointId == nil || snapshot.capabilityObservations?.allSatisfy({
                  $0.endpointId == snapshot.publisherEndpointId
              }) != false,
              snapshot.capabilityObservations?.allSatisfy({
                  $0.projectId == sessionId && !$0.requestId.isEmpty && !$0.endpointId.isEmpty
                      && ["needs_binding", "not_found", "discovered", "configured",
                          "initialized", "credential_missing", "version_conflict",
                          "unsupported"].contains($0.state)
                      && ($0.artifactDigest.map(Self.validDigest) ?? true)
              }) != false,
              Set((snapshot.capabilityObservations ?? []).map(\.id)).count
                  == (snapshot.capabilityObservations?.count ?? 0),
              (snapshot.modelCatalog?.count ?? 0) <= 32,
              snapshot.modelCatalog?.allSatisfy({ $0.models.count <= 64 }) ?? true,
              snapshot.backbone?.projectId == nil || snapshot.backbone?.projectId == sessionId,
              (snapshot.backbone?.nodes.count ?? 0) <= 512,
              (snapshot.backbone?.relations.count ?? 0) <= 1_024,
              (snapshot.repositoryGraphs?.count ?? 0) <= 64,
              snapshot.repositoryGraphs?.allSatisfy({
                  $0.projectId == sessionId && $0.nodes.count <= 256
                      && $0.relations.count <= 512
                      && ($0.codeMap?.valid() ?? true)
                      && validArchitectureHypotheses($0.architectureHypotheses)
                      && ($0.analysisStatus != "UNAVAILABLE" ||
                          ($0.analysisErrorCode != nil && $0.nodes.isEmpty
                           && $0.relations.isEmpty && $0.codeMap == nil
                           && $0.totalNodes == 0 && $0.totalRelations == 0))
              }) != false,
              (snapshot.cortex?.count ?? 0) <= 32,
              Set((snapshot.cortex ?? []).map(\.endpointId)).count == (snapshot.cortex?.count ?? 0),
              snapshot.cortex?.allSatisfy({
                  $0.projectId == sessionId && !$0.endpointId.isEmpty
                      && $0.endpointId.count <= 128
                      && (512...262_144).contains($0.maxTokens)
                      && ["disabled", "loaded", "succeeded", "unavailable", "degraded"].contains($0.state)
                      && validCortexPacket($0.packet)
              }) ?? true,
              ProjectMeshKnowledgeValidation.valid(
                  snapshot.knowledge, correctedIds: snapshot.supersededKnowledgeRecordIds,
                  projectId: sessionId
              ),
              ProjectAuxiliaryPolicyValidation.valid(snapshot.execution,
                                                     restrictions: snapshot.restrictions,
                                                     environment: snapshot.environment,
                                                     projectId: sessionId)
        else { return false }
        return true
    }

    private static func validArchitectureHypotheses(
        _ hypotheses: [ProjectRepositoryGraph.ArchitectureHypothesis]?
    ) -> Bool {
        guard let hypotheses else { return true }
        return hypotheses.count <= 8 && hypotheses.allSatisfy { item in
            ["SUPPORTED", "CANDIDATE", "CONTRADICTED",
             "INSUFFICIENT_EVIDENCE"].contains(item.status)
                && item.evidence.count <= 16 && item.contradictions.count <= 16
                && item.unknowns.count <= 4
        }
    }

    private static func validCortexPacket(_ packet: ProjectCortexPacketStatus?) -> Bool {
        guard let packet else { return true }
        return packet.included >= 0 && packet.included <= 256
            && packet.omitted >= 0 && packet.omitted <= 256
            && packet.rawEstimatedTokens >= 0
            && packet.selectedEstimatedTokens >= 0
            && packet.omittedEstimatedTokens >= 0
            && packet.deduplicatedLines >= 0
    }

    private static func validBindings(_ value: Any?, projectId: String) -> Bool {
        guard value != nil else { return true }
        guard let bindings = value as? [[String: Any]], bindings.count <= 64 else { return false }
        let allowed: Set<String> = [
            "bindingId", "projectId", "endpointId", "repositoryId", "displayName",
            "localPathHint", "available", "revision",
        ]
        var ids = Set<String>()
        var locations = Set<String>()
        for binding in bindings {
            guard Set(binding.keys).isSubset(of: allowed),
                  let bindingId = boundedString(binding["bindingId"], max: 128),
                  boundedString(binding["projectId"], max: 128) == projectId,
                  let endpointId = boundedString(binding["endpointId"], max: 128),
                  let repositoryId = boundedString(binding["repositoryId"], max: 512),
                  boundedString(binding["displayName"], max: 160) != nil,
                  binding["available"] is Bool,
                  ids.insert(bindingId).inserted,
                  locations.insert("\(endpointId)\u{0}\(repositoryId)").inserted
            else { return false }
            if binding["localPathHint"] != nil,
               boundedString(binding["localPathHint"], max: 4_096) == nil { return false }
            if binding["revision"] != nil,
               boundedString(binding["revision"], max: 512) == nil { return false }
        }
        return true
    }

    private static func validPeers(_ value: Any?, projectId: String) -> Bool {
        guard value != nil else { return true }
        guard let peers = value as? [[String: Any]], peers.count <= 64 else { return false }
        let allowed: Set<String> = [
            "projectId", "repositoryId", "peer", "via", "relation", "through", "updatedAt",
        ]
        let vias: Set<String> = ["database", "kafka", "api"]
        let relations: Set<String> = ["produces", "consumes", "calls", "called_by", "shares"]
        for peer in peers {
            guard Set(peer.keys).isSubset(of: allowed),
                  boundedString(peer["projectId"], max: 128) == projectId,
                  boundedString(peer["repositoryId"], max: 512) != nil,
                  boundedString(peer["peer"], max: 160) != nil,
                  let via = peer["via"] as? String, vias.contains(via),
                  let relation = peer["relation"] as? String, relations.contains(relation),
                  peer["updatedAt"] is NSNumber
            else { return false }
            if peer["through"] != nil, boundedString(peer["through"], max: 160) == nil { return false }
        }
        return true
    }

    private static func validPayload(_ payload: [String: Any]) -> Bool {
        for key in ["summary", "question", "answer", "reason"] {
            if payload[key] != nil, boundedString(payload[key], max: 1_000) == nil { return false }
        }
        guard let capsule = payload["capsule"] as? [String: Any] else {
            return payload["capsule"] == nil
        }
        return validCapsule(capsule)
    }

    private static func validCapsule(_ capsule: [String: Any]) -> Bool {
        guard Set(capsule.keys).isSubset(of: capsuleKeys),
              let source = capsule["sourceProvider"] as? String, providers.contains(source),
              let target = capsule["targetProvider"] as? String, providers.contains(target),
              boundedString(capsule["taskId"], max: 128) != nil,
              boundedString(capsule["goal"], max: 1_000) != nil,
              boundedString(capsule["currentStatus"], max: 1_000) != nil,
              boundedStrings(capsule["filesChanged"], count: 64, length: 1_024),
              boundedStrings(capsule["dependencies"], count: 32, length: 128),
              boundedStrings(capsule["resourceClaims"], count: 64, length: 1_024),
              boundedStrings(capsule["remainingWork"], count: 32, length: 1_000),
              boundedStrings(capsule["importantDecisions"], count: 16, length: 1_000)
        else { return false }
        if let workingTree = capsule["workingTree"],
           !workingTreeStates.contains(boundedString(workingTree, max: 16) ?? "") { return false }
        if let targetModel = capsule["targetModel"] as? String,
           !validModelId(targetModel) { return false }
        if capsule["targetModel"] != nil && !(capsule["targetModel"] is String) { return false }
        if capsule["userComment"] != nil,
           boundedString(capsule["userComment"], max: 1_000) == nil { return false }
        if let checkpoint = capsule["checkpoint"] {
            guard let value = checkpoint as? [String: Any], Set(value.keys) == checkpointKeys,
                  CapsuleCheckpoint.statuses.contains(boundedString(value["status"], max: 16) ?? ""),
                  let files = value["files"] as? Int, files >= 0,
                  boundedStrings(value["excluded"], count: 32, length: 1_024)
            else { return false }
        }
        if source == "grok_bot" {
            guard boundedString(capsule["sourceActorId"], max: 128) != nil else { return false }
        } else if capsule["sourceActorId"] != nil { return false }
        if target == "grok_bot" {
            guard boundedString(capsule["targetActorId"], max: 128) != nil else { return false }
        } else if capsule["targetActorId"] != nil { return false }
        return true
    }

    static func validModelId(_ value: String) -> Bool {
        value.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,159}$"#,
                    options: .regularExpression) != nil
    }

    private static func boundedString(_ value: Any?, max: Int) -> String? {
        guard let value = value as? String, !value.isEmpty, value.count <= max else { return nil }
        return value
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func boundedStrings(_ value: Any?, count: Int, length: Int) -> Bool {
        guard let values = value as? [Any], values.count <= count else { return false }
        return values.allSatisfy { boundedString($0, max: length) != nil }
    }
}
