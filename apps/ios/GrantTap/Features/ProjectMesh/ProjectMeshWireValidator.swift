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

    static let snapshotKeys: Set<String> = [
        "type", "sessionId", "projectId", "project", "tasks", "executions",
        "bindings", "peers", "skills", "incomplete", "execution", "modelCatalog",
        "claims", "dependencies", "events", "generatedAt",
    ]

    static func validSnapshot(_ data: Data) -> Bool {
        snapshotRejectReason(data) == nil
    }

    /// Why a computer snapshot never became Mesh on the phone. The Mac always
    /// attaches `modelCatalog` (models or `not_reported`) and may attach
    /// `execution`; rejecting those keys left Projects empty while chats arrived.
    static func snapshotRejectReason(_ data: Data) -> String? {
        if data.count > 256 * 1_024 { return "mesh snapshot too large (\(data.count) bytes)" }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "mesh snapshot is not an object"
        }
        let extra = Set(value.keys).subtracting(snapshotKeys).sorted()
        if !extra.isEmpty { return "mesh snapshot extra keys \(extra.joined(separator: ","))" }
        guard value["type"] as? String == "mesh.snapshot" else { return "mesh snapshot wrong type" }
        guard let sessionId = boundedString(value["sessionId"], max: 128),
              sessionId == boundedString(value["projectId"], max: 128) else {
            return "mesh snapshot sessionId is not projectId"
        }
        if !validBindings(value["bindings"], projectId: sessionId) { return "mesh snapshot bindings rejected" }
        if !validPeers(value["peers"], projectId: sessionId) { return "mesh snapshot peers rejected" }
        if !validSkills(value["skills"]) { return "mesh snapshot skills rejected" }
        if !validIncomplete(value["incomplete"]) { return "mesh snapshot incomplete rejected" }
        if !validExecution(value["execution"]) { return "mesh snapshot execution rejected" }
        if !validModelCatalog(value["modelCatalog"]) { return "mesh snapshot modelCatalog rejected" }
        guard let tasks = value["tasks"] as? [Any], tasks.count <= 64 else {
            return "mesh snapshot tasks rejected"
        }
        guard let executions = value["executions"] as? [Any], executions.count <= 128 else {
            return "mesh snapshot executions rejected"
        }
        guard let claims = value["claims"] as? [Any], claims.count <= 128 else {
            return "mesh snapshot claims rejected"
        }
        guard let dependencies = value["dependencies"] as? [Any], dependencies.count <= 128 else {
            return "mesh snapshot dependencies rejected"
        }
        guard let events = value["events"] as? [Any], events.count <= 128 else {
            return "mesh snapshot events rejected"
        }
        for (index, event) in events.enumerated() {
            guard JSONSerialization.isValidJSONObject(event),
                  let encoded = try? JSONSerialization.data(withJSONObject: event),
                  validEvent(encoded) else {
                return "mesh snapshot event[\(index)] rejected"
            }
        }
        return nil
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

    private static func validSkills(_ value: Any?) -> Bool {
        guard value != nil else { return true }
        guard let skills = value as? [[String: Any]], skills.count <= 64 else { return false }
        let allowed: Set<String> = [
            "name", "description", "version", "digest", "source", "state",
        ]
        let states: Set<String> = ["installed", "available", "used", "unknown"]
        var names = Set<String>()
        for skill in skills {
            guard Set(skill.keys).isSubset(of: allowed),
                  let name = boundedString(skill["name"], max: 160),
                  names.insert(name).inserted
            else { return false }
            if skill["description"] != nil,
               boundedString(skill["description"], max: 1_000) == nil { return false }
            if skill["version"] != nil,
               boundedString(skill["version"], max: 128) == nil { return false }
            if skill["digest"] != nil,
               boundedString(skill["digest"], max: 128) == nil { return false }
            if skill["source"] != nil,
               boundedString(skill["source"], max: 512) == nil { return false }
            if skill["state"] != nil {
                guard let state = boundedString(skill["state"], max: 16),
                      states.contains(state) else { return false }
            }
        }
        return true
    }

    private static func validIncomplete(_ value: Any?) -> Bool {
        value == nil || value is Bool
    }

    private static func validExecution(_ value: Any?) -> Bool {
        guard value != nil else { return true }
        guard let execution = value as? [String: Any] else { return false }
        let allowed: Set<String> = [
            "mode", "targetEndpointId", "revision", "hostGrantId",
            "hostGrantStatus", "offlineBehavior",
        ]
        let modes: Set<String> = ["distributed", "pinned"]
        let grants: Set<String> = ["none", "pending", "applied", "unavailable"]
        let offline: Set<String> = ["reject", "queueUntilDeadline"]
        guard Set(execution.keys).isSubset(of: allowed),
              let mode = execution["mode"] as? String, modes.contains(mode),
              integer(execution["revision"]).map({ $0 > 0 }) == true
        else { return false }
        if mode == "pinned", boundedString(execution["targetEndpointId"], max: 128) == nil {
            return false
        }
        if execution["targetEndpointId"] != nil,
           boundedString(execution["targetEndpointId"], max: 128) == nil { return false }
        if execution["hostGrantId"] != nil,
           boundedString(execution["hostGrantId"], max: 128) == nil { return false }
        if let status = execution["hostGrantStatus"],
           !grants.contains(boundedString(status, max: 16) ?? "") { return false }
        if let behavior = execution["offlineBehavior"],
           !offline.contains(boundedString(behavior, max: 32) ?? "") { return false }
        return true
    }

    private static func validModelCatalog(_ value: Any?) -> Bool {
        guard value != nil else { return true }
        guard let catalogs = value as? [[String: Any]], catalogs.count <= 32 else { return false }
        let catalogKeys: Set<String> = ["endpointId", "observedAt", "stale", "models", "reason"]
        let modelKeys: Set<String> = [
            "modelId", "provider", "endpointId", "source", "label", "observedAt",
        ]
        let catalogProviders: Set<String> = ["claude", "codex", "cursor", "grok"]
        let sources: Set<String> = ["observed", "advertised"]
        for catalog in catalogs {
            guard Set(catalog.keys).isSubset(of: catalogKeys),
                  boundedString(catalog["endpointId"], max: 128) != nil,
                  catalog["observedAt"] is NSNumber,
                  let models = catalog["models"] as? [[String: Any]], models.count <= 64
            else { return false }
            if catalog["stale"] != nil, !(catalog["stale"] is Bool) { return false }
            if catalog["reason"] != nil,
               boundedString(catalog["reason"], max: 240) == nil { return false }
            for model in models {
                guard Set(model.keys).isSubset(of: modelKeys),
                      boundedString(model["modelId"], max: 160) != nil,
                      let provider = model["provider"] as? String, catalogProviders.contains(provider),
                      boundedString(model["endpointId"], max: 128) != nil,
                      let source = model["source"] as? String, sources.contains(source),
                      model["observedAt"] is NSNumber
                else { return false }
                if model["label"] != nil, boundedString(model["label"], max: 160) == nil { return false }
            }
        }
        return true
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber, CFNumberIsFloatType(value) == false {
            return value.intValue
        }
        return nil
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
