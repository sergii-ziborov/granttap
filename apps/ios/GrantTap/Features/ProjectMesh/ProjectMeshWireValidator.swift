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
        "targetProvider", "targetActorId", "targetComputer", "repository", "baseSha", "branch",
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
            "type", "sessionId", "projectId", "project", "tasks", "executions",
            "bindings", "peers", "claims", "dependencies", "events", "generatedAt",
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
        return events.allSatisfy { event in
            guard JSONSerialization.isValidJSONObject(event),
                  let encoded = try? JSONSerialization.data(withJSONObject: event) else { return false }
            return validEvent(encoded)
        }
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

    private static func boundedString(_ value: Any?, max: Int) -> String? {
        guard let value = value as? String, !value.isEmpty, value.count <= max else { return nil }
        return value
    }

    private static func boundedStrings(_ value: Any?, count: Int, length: Int) -> Bool {
        guard let values = value as? [Any], values.count <= count else { return false }
        return values.allSatisfy { boundedString($0, max: length) != nil }
    }
}
