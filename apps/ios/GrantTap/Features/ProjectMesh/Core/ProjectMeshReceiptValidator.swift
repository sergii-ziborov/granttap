import CryptoKit
import Foundation

enum ProjectMeshReceiptValidator {
    static func valid(
        _ receipt: ProjectHandoffReceipt,
        for event: ProjectMeshEvent,
        in snapshot: ProjectMeshSnapshot?
    ) -> Bool {
        guard event.eventType == "HANDOFF_ACCEPTED",
              receipt.taskId == event.taskId,
              receipt.targetSessionId == event.sourceSessionId,
              let request = snapshot?.events.reversed().first(where: {
                  $0.eventType == "HANDOFF_REQUEST"
                      && $0.taskId == event.taskId
                      && $0.sourceSessionId == receipt.sourceSessionId
                      && $0.payload.capsule != nil
              }),
              let capsule = request.payload.capsule,
              capsule.taskId == event.taskId,
              let digest = capsuleHash(capsule)
        else { return false }
        return digest == receipt.capsuleHash.lowercased()
    }

    static func capsuleHash(_ capsule: TaskCapsule) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(capsule) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
