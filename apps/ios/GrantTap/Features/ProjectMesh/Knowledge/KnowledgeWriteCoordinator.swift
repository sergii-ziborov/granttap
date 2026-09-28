import SwiftUI

struct KnowledgeWriteRequest: Codable {
    let type = "knowledge.write"
    let projectId: String
    let taskId: String
    let recordId: String
    let content: String
    let repositoryId: String?
    let supersedesRecordId: String?
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case type, projectId, taskId, recordId, content, repositoryId, supersedesRecordId, createdAt
    }
}

struct KnowledgeWriteResult: Codable {
    let type: String
    let projectId: String
    let taskId: String
    let recordId: String
    let status: String
    let reason: String?
    let createdAt: Double
}

@MainActor
final class KnowledgeWriteCoordinator: ObservableObject {
    static let shared = KnowledgeWriteCoordinator()
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var results: [String: KnowledgeWriteResult] = [:]
    private var expectedRooms: [String: String] = [:]
    private var requests: [String: KnowledgeWriteRequest] = [:]

    func submit(
        model: AppModel, projectId: String, taskId: String,
        content: String, repositoryId: String? = nil, supersedesRecordId: String? = nil
    ) -> String? {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 4_096,
              model.meshSnapshots[projectId]?.tasks.contains(where: { $0.taskId == taskId }) == true,
              let room = availableRoom(model: model, projectId: projectId),
              let client = model.relaysByRoom[room] else { return nil }
        let recordId = UUID().uuidString.lowercased()
        let request = KnowledgeWriteRequest(
            projectId: projectId, taskId: taskId, recordId: recordId,
            content: clean, repositoryId: repositoryId, supersedesRecordId: supersedesRecordId,
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
        expectedRooms[recordId] = room
        requests[recordId] = request
        pending.insert(recordId)
        client.send(payload: request, ttl: 5 * 60, deliveryId: "knowledge-\(recordId)")
        return recordId
    }

    /// Reuse the exact record identity and timestamp if a relay receipt was lost.
    func retry(_ recordId: String, model: AppModel) -> Bool {
        guard pending.contains(recordId), let room = expectedRooms[recordId],
              let request = requests[recordId],
              Date().timeIntervalSince1970 * 1_000 - request.createdAt < 4 * 60_000,
              let client = model.relaysByRoom[room],
              model.connectionRegistry.connections.first(where: { $0.id == room })
                .map({ model.snapshotForConnection($0).phase == .live }) == true else { return false }
        client.send(payload: request, ttl: 60, deliveryId: "knowledge-\(recordId)")
        return true
    }

    func receive(_ result: KnowledgeWriteResult, fromRoom room: String) {
        guard result.type == "knowledge.write.result", result.projectId.count <= 128,
              result.taskId.count <= 128, ["recorded", "rejected"].contains(result.status),
              expectedRooms[result.recordId] == room else { return }
        pending.remove(result.recordId)
        expectedRooms[result.recordId] = nil
        requests[result.recordId] = nil
        results[result.recordId] = result
        if results.count > 64 { results.removeValue(forKey: results.keys.sorted().first!) }
    }

    private func availableRoom(model: AppModel, projectId: String) -> String? {
        let rooms = model.ownComputerRooms(for: projectId)
        return rooms.sorted().first { room in
            guard let connection = model.connectionRegistry.connections.first(where: { $0.id == room })
            else { return false }
            return !connection.pairing.isHub
                && model.snapshotForConnection(connection).phase == .live
        }
    }
}
