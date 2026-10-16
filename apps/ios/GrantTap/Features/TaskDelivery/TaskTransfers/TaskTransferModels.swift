import Foundation

struct TaskTransferNotice: Codable, Equatable {
    var phase: String? = nil
    var queuedAt: Double? = nil
    var targetComputerId: String? = nil
    var targetProvider: String? = nil
    let sourceSessionId: String
    let targetSessionId: String?
    let projectId: String
    let taskId: String
    let capsuleHash: String
    let acceptedAt: Double?
    var continuedAt: Double?

    var isPending: Bool { phase == "pending" }
    var confirmationTime: Double { max(acceptedAt ?? 0, queuedAt ?? 0) }
    var isWellFormed: Bool {
        guard !sourceSessionId.isEmpty, !projectId.isEmpty, !taskId.isEmpty,
              capsuleHash.count == 64, capsuleHash.allSatisfy({ "0123456789abcdef".contains($0) }),
              [sourceSessionId, projectId, taskId].allSatisfy({ $0.utf8.count <= 256 }) else { return false }
        if isPending {
            guard let queuedAt, queuedAt.isFinite, queuedAt >= 0,
                  targetComputerId?.isEmpty == false, acceptedAt == nil, targetSessionId == nil else { return false }
        } else {
            guard phase == nil || phase == "accepted", let acceptedAt, acceptedAt.isFinite,
                  acceptedAt >= 0, targetSessionId?.isEmpty == false else { return false }
        }
        return continuedAt.map { $0.isFinite && $0 > confirmationTime } ?? true
    }
}

struct TaskTransferContinue: Codable, Equatable {
    var type = "task.transfer.continue"
    let sessionId: String
    let projectId: String
    let taskId: String
    let capsuleHash: String
    let requestId: String
    let createdAt: Double
}

struct TaskTransferContinueResult: Decodable {
    let sessionId: String
    let projectId: String
    let taskId: String
    let capsuleHash: String
    let requestId: String
    let accepted: Bool
    let notice: TaskTransferNotice?
}

struct TaskTransferProgress {
    var pending: [String: TaskTransferContinue] = [:]
    var confirmed: [String: TaskTransferNotice] = [:]
    var errors: [String: String] = [:]
}
