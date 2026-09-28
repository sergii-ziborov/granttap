import Foundation

public enum EngineClientError: Error, CustomStringConvertible, Sendable {
    case invalidRequest, invalidFrame, incompatibleResponse, remoteFailure
    case unavailable, deadlineExceeded, socketUntrusted, busy

    public var description: String {
        switch self {
        case .invalidRequest: "The Engine request is invalid."
        case .invalidFrame: "The Engine sent an invalid frame."
        case .incompatibleResponse: "The Engine response does not match this request."
        case .remoteFailure: "The Engine could not complete this read."
        case .unavailable: "The local Engine is unavailable."
        case .deadlineExceeded: "The Engine did not respond in time."
        case .socketUntrusted: "The Engine socket is not owned and protected by this user."
        case .busy: "Another Engine read is already in progress."
        }
    }
}

public enum EngineQuery: Sendable {
    case version
    case projects(afterProjectId: String?)
    case resolveFolder(String)
    case project(String)
    case bindings(String)
    case policy(String)
    case coverage(String)
    case backbone(String)
    case knowledge(projectId: String, taskId: String?, beforeVersion: UInt64?)
    case invocations(projectId: String, taskId: String?, beforeSequence: UInt64?)
    case meshProject(String)
    case workspace
    case taskActivity(projectId: String, taskId: String)

    var operation: String {
        switch self {
        case .version: "engine.version"
        case .projects: "project.list"
        case .resolveFolder: "project.resolve"
        case .project: "project.get"
        case .bindings: "project.list_bindings"
        case .policy: "policy.get"
        case .coverage: "policy.coverage"
        case .backbone: "graph.get_backbone"
        case .knowledge: "memory.history"
        case .invocations: "invocation.history"
        case .meshProject: "desktop.project"
        case .workspace: "desktop.workspace"
        case .taskActivity: "desktop.task_activity"
        }
    }

    var expectedOperation: String {
        switch self {
        case .version: "engine.version"
        case .projects: "project.listed"
        case .resolveFolder: "project.resolved"
        case .project: "project.found"
        case .bindings: "project.bindings"
        case .policy: "policy.found"
        case .coverage: "policy.coverage"
        case .backbone: "graph.backbone"
        case .knowledge: "memory.history"
        case .invocations: "invocation.history"
        case .meshProject: "desktop.project"
        case .workspace: "desktop.workspace"
        case .taskActivity: "desktop.task_activity"
        }
    }

    var projectId: String? {
        switch self {
        case .version, .projects, .resolveFolder, .workspace: nil
        case let .project(id), let .bindings(id), let .policy(id),
             let .coverage(id), let .backbone(id), let .meshProject(id): id
        case let .knowledge(id, _, _), let .invocations(id, _, _): id
        case let .taskActivity(id, _): id
        }
    }

    var taskId: String? {
        switch self {
        case let .knowledge(_, id, _), let .invocations(_, id, _): id
        case let .taskActivity(_, id): id
        default: nil
        }
    }

    var input: [String: Any]? {
        if case let .resolveFolder(path) = self { return ["local_root": path] }
        if case let .projects(afterProjectId) = self {
            var fields: [String: Any] = ["limit": 50]
            if let afterProjectId { fields["after_project_id"] = afterProjectId }
            return fields
        }
        guard let projectId else { return nil }
        var fields: [String: Any] = ["project_id": projectId]
        switch self {
        case let .knowledge(_, taskId, beforeVersion):
            fields["limit"] = 24
            fields["include_superseded"] = false
            if let taskId { fields["task_id"] = taskId }
            else { fields["visibility"] = "project" }
            if let beforeVersion { fields["before_version"] = beforeVersion }
        case let .invocations(_, taskId, beforeSequence):
            fields["limit"] = 32
            fields["tail"] = true
            if let taskId { fields["task_id"] = taskId }
            if let beforeSequence { fields["before_sequence"] = beforeSequence }
        case let .taskActivity(_, taskId):
            fields["task_id"] = taskId
        default: break
        }
        return fields
    }

    var cursor: UInt64? {
        switch self {
        case let .knowledge(_, _, value), let .invocations(_, _, value): value
        default: nil
        }
    }
}

public enum EngineCodec {
    public static let maxFrameBytes = 512 * 1_024

    public static func encode(_ query: EngineQuery, requestId: String) throws -> Data {
        guard !requestId.isEmpty, requestId.utf8.count <= 128,
              !requestId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw EngineClientError.invalidRequest }
        var request: [String: Any] = [
            "protocol_version": 1, "request_id": requestId, "operation": query.operation,
        ]
        if case let .resolveFolder(path) = query {
            guard path.hasPrefix("/"), path.utf8.count <= 4_096,
                  !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  URL(fileURLWithPath: path).standardizedFileURL.path == path else {
                throw EngineClientError.invalidRequest
            }
            request["input"] = query.input
        } else if case let .projects(afterProjectId) = query {
            if let afterProjectId {
                guard !afterProjectId.isEmpty, afterProjectId.utf8.count <= 128,
                      !afterProjectId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                else { throw EngineClientError.invalidRequest }
            }
            request["input"] = query.input
        } else if let projectId = query.projectId {
            guard !projectId.isEmpty, projectId.utf8.count <= 128,
                  !projectId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw EngineClientError.invalidRequest }
            if let taskId = query.taskId {
                guard !taskId.isEmpty, taskId.utf8.count <= 128,
                      !taskId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                else { throw EngineClientError.invalidRequest }
            }
            if let cursor = query.cursor, cursor == 0 || cursor > Int64.max {
                throw EngineClientError.invalidRequest
            }
            request["input"] = query.input
        }
        let payload = try JSONSerialization.data(withJSONObject: request)
        guard !payload.isEmpty, payload.count <= maxFrameBytes else {
            throw EngineClientError.invalidRequest
        }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    public static func result(
        _ payload: Data, for query: EngineQuery, requestId: String
    ) throws -> Data {
        guard !payload.isEmpty, payload.count <= maxFrameBytes,
              let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              root["protocol_version"] as? Int == 1,
              root["request_id"] as? String == requestId,
              let status = root["status"] as? String else {
            throw EngineClientError.incompatibleResponse
        }
        guard status == "ok" else { throw EngineClientError.remoteFailure }
        guard let result = root["result"] as? [String: Any],
              result["operation"] as? String == query.expectedOperation,
              matchesProject(result, query: query) else {
            throw EngineClientError.incompatibleResponse
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    private static func matchesProject(_ result: [String: Any], query: EngineQuery) -> Bool {
        if case .workspace = query { return MeshWorkspaceCodec.matches(result) }
        if case let .projects(afterProjectId) = query {
            return ProjectCatalogCodec.matches(result, afterProjectId: afterProjectId)
        }
        if case .resolveFolder = query {
            guard let resolution = result["resolution"] as? [String: Any],
                  let id = resolution["project_id"] as? String,
                  !id.isEmpty, id.utf8.count <= 128,
                  !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return false }
            return resolution["compatibility_mode"] as? Bool == false
        }
        guard let projectId = query.projectId else {
            return result["protocol_version"] as? Int == 1
        }
        if case .meshProject = query {
            return MeshProjectCodec.matches(result, projectId: projectId)
        }
        if case let .taskActivity(_, taskId) = query {
            return TaskActivityCodec.matches(result, projectId: projectId, taskId: taskId)
        }
        switch query {
        case .version, .projects, .resolveFolder, .workspace: return true
        case .meshProject: return false
        case .taskActivity: return false
        case .project:
            return (result["project"] as? [String: Any])?["project_id"] as? String == projectId
        case .bindings:
            guard let bindings = result["bindings"] as? [[String: Any]] else { return false }
            return bindings.allSatisfy { $0["project_id"] as? String == projectId }
        case .policy:
            return (result["policy"] as? [String: Any])?["project_id"] as? String == projectId
        case .coverage:
            return EngineCoverageCodec.matches(result, projectId: projectId)
        case .backbone:
            return (result["backbone"] as? [String: Any])?["project_id"] as? String == projectId
        case .knowledge, .invocations:
            return EngineHistoryCodec.matches(result, query: query, projectId: projectId)
        }
    }
}
