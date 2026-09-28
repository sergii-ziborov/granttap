#if targetEnvironment(macCatalyst)
import Foundation

private enum MacLocalPolicyPayload: Decodable {
    case status(ProjectPolicyStatus)
    case ack(ProjectPolicyAck)
    case rejected(ProjectPolicyRejected)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "project.policy.status": self = .status(try ProjectPolicyStatus(from: decoder))
        case "project.policy.ack": self = .ack(try ProjectPolicyAck(from: decoder))
        case "project.policy.rejected": self = .rejected(try ProjectPolicyRejected(from: decoder))
        default: throw MacLocalMCPError.incompatible
        }
    }
    private enum CodingKeys: String, CodingKey { case type }
}

private struct MacLocalPolicyResult: Decodable {
    let operation: String
    let project_id: String
    let endpoint_id: String
    let accepted: Bool
    let payloads: [MacLocalPolicyPayload]
}

extension MacLocalMCPModel {
    fileprivate func policy(projectId: String, request: ProjectPolicySet? = nil) async throws
        -> MacLocalPolicyResult {
        guard let socket = status?.desktopEngineSocket, let endpoint = status?.endpointId else {
            throw MacLocalMCPError.unavailable
        }
        let operation = request == nil ? "desktop.policy_status" : "desktop.policy_set"
        var input = ["project_id": projectId]
        if let request {
            input["request"] = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        }
        let data = try await MacLocalMCPClient.read(socketPath: socket, operation: operation, input: input)
        let result = try JSONDecoder().decode(MacLocalPolicyResult.self, from: data)
        guard result.operation == operation, result.project_id == projectId,
              result.endpoint_id == endpoint, !result.payloads.isEmpty,
              result.payloads.count <= 8 else { throw MacLocalMCPError.incompatible }
        for payload in result.payloads {
            let valid: Bool
            switch payload {
            case .status(let value):
                valid = value.projectId == projectId && ProjectGovernanceWireValidator.validStatus(value)
            case .ack(let value):
                valid = value.projectId == projectId && value.acknowledgement.endpointId == endpoint
                    && ProjectGovernanceWireValidator.validAck(value)
            case .rejected(let value):
                valid = value.projectId == projectId && ProjectGovernanceWireValidator.validRejected(value)
            }
            guard valid else { throw MacLocalMCPError.incompatible }
        }
        return result
    }
}

extension AppModel {
    func refreshLocalProjectPolicy(projectId: String) async {
        guard let reader = localMCPReader, reader.isReady else { return }
        do {
            acceptLocalPolicy(try await reader.policy(projectId: projectId))
        } catch {
            projectPolicyErrors[projectId] = L("Could not read Mesh policy from this Mac. Retry.")
        }
    }

    func submitLocalProjectPolicy(_ request: ProjectPolicySet) -> Bool {
        guard let reader = localMCPReader, reader.isReady,
              let endpoint = reader.status?.endpointId,
              reader.meshSnapshots[request.projectId]?.bindings?.contains(where: {
                  $0.endpointId == endpoint && $0.available
              }) == true else { return false }
        pendingProjectPolicyRevisions[request.projectId] = request.policy.revision
        projectPolicyErrors.removeValue(forKey: request.projectId)
        Task {
            do {
                let result = try await reader.policy(projectId: request.projectId, request: request)
                acceptLocalPolicy(result)
            } catch {
                pendingProjectPolicyRevisions.removeValue(forKey: request.projectId)
                projectPolicyErrors[request.projectId] = L("Could not apply Mesh policy on this Mac. Your edit is kept; retry.")
            }
        }
        return true
    }

    private func acceptLocalPolicy(_ result: MacLocalPolicyResult) {
        // Rejections are processed last so a following canonical refresh keeps the refusal visible.
        for payload in result.payloads {
            switch payload {
            case .status(let value): receive(value, fromRoom: "local-mac", recordSource: false)
            case .ack(let value): receive(value, fromRoom: "local-mac", recordSource: false)
            case .rejected: break
            }
        }
        for payload in result.payloads {
            if case .rejected(let value) = payload {
                receive(value, fromRoom: "local-mac", recordSource: false)
            }
        }
    }
}
#endif
