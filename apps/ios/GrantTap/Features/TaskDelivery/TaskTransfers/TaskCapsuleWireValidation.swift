import Foundation

/// Bounded transfer metadata accepted by the Apple clients.
enum TaskCapsuleWireValidation {
    private static let capsuleKeys: Set<String> = [
        "title", "launch", "contextHash", "taskId", "goal", "currentStatus",
        "sourceProvider", "sourceActorId", "sourceComputer",
        "targetProvider", "targetActorId", "targetComputer", "targetModel", "userComment",
        "repository", "baseSha", "branch",
        "latestCommit", "dirtyDiffHash", "workingTree", "filesChanged", "testsStatus",
        "dependencies", "resourceClaims", "remainingWork", "importantDecisions", "checkpoint", "createdAt",
    ]
    private static let checkpointKeys: Set<String> = ["status", "files", "excluded"]
    private static let workingTreeStates: Set<String> = ["clean", "dirty", "unknown"]
    private static let providers: Set<String> = ["claude", "codex", "cursor", "grok", "grok_bot"]

    static func valid(_ capsule: [String: Any]) -> Bool {
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
        if capsule["title"] != nil, boundedString(capsule["title"], max: 160) == nil { return false }
        if capsule["launch"] != nil, capsule["launch"] as? String != "on_message" { return false }
        if let digest = capsule["contextHash"] {
            guard let value = digest as? String, validDigest(value) else { return false }
        }
        if let workingTree = capsule["workingTree"],
           !workingTreeStates.contains(boundedString(workingTree, max: 16) ?? "") { return false }
        if let targetModel = capsule["targetModel"] as? String,
           !ProjectMeshWireValidator.validModelId(targetModel) { return false }
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
