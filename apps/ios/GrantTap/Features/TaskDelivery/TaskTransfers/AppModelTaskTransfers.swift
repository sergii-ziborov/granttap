import Foundation

@MainActor
extension AppModel {
    var usesLocalTransferComputer: Bool {
        #if targetEnvironment(macCatalyst)
        localMCPReader?.isReady == true
        #else
        false
        #endif
    }

    func transferNotice(for session: SessionInfo) -> TaskTransferNotice? {
        guard var notice = session.transfer, notice.isWellFormed else { return nil }
        let confirmed = taskTransfers.confirmed[session.sessionId]
        if confirmed?.capsuleHash == notice.capsuleHash, let continuedAt = confirmed?.continuedAt {
            notice.continuedAt = max(notice.continuedAt ?? 0, continuedAt)
        }
        return notice
    }

    func continueTransferredTask(_ session: SessionInfo) {
        guard let notice = transferNotice(for: session), notice.continuedAt == nil,
              notice.sourceSessionId == session.sessionId,
              notice.projectId == session.projectId, notice.taskId == session.taskId,
              taskTransfers.pending[session.sessionId] == nil else { return }
        let command = TaskTransferContinue(sessionId: session.sessionId, projectId: notice.projectId,
            taskId: notice.taskId, capsuleHash: notice.capsuleHash,
            requestId: UUID().uuidString.lowercased(), createdAt: Date().timeIntervalSince1970 * 1_000)
        taskTransfers.pending[session.sessionId] = command
        taskTransfers.errors[session.sessionId] = nil
        Task { [self] in
            #if targetEnvironment(macCatalyst)
            if usesLocalTaskDelivery(for: session) {
                do {
                    let input: [String: Any] = ["session_id": session.sessionId, "project_id": notice.projectId,
                        "task_id": notice.taskId, "capsule_hash": notice.capsuleHash]
                    let data = try await MacNativeTransport.invoke(operation: "desktop.transfer_continue", input: input)
                    struct Response: Decodable { let accepted: Bool; let notice: TaskTransferNotice? }
                    let result = try JSONDecoder().decode(Response.self, from: data)
                    finishTransferContinuation(command, accepted: result.accepted, notice: result.notice)
                } catch { finishTransferContinuation(command, accepted: false, notice: nil) }
                return
            }
            #endif
            guard let relay = relayForSession(session.sessionId) else {
                finishTransferContinuation(command, accepted: false, notice: nil); return
            }
            relay.send(payload: command, ttl: 60) { [weak self] error in
                if error != nil {
                    Task { @MainActor in self?.finishTransferContinuation(command, accepted: false, notice: nil) }
                }
            }
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if taskTransfers.pending[session.sessionId]?.requestId == command.requestId {
                finishTransferContinuation(command, accepted: false, notice: nil)
            }
        }
    }

    func receive(_ result: TaskTransferContinueResult, fromRoom room: String) {
        guard let pending = taskTransfers.pending[result.sessionId], pending.requestId == result.requestId,
              pending.taskId == result.taskId, pending.projectId == result.projectId,
              pending.capsuleHash == result.capsuleHash,
              sourceRoom(forSessionId: result.sessionId) == room else { return }
        finishTransferContinuation(pending, accepted: result.accepted, notice: result.notice)
    }

    private func finishTransferContinuation(_ command: TaskTransferContinue, accepted: Bool,
                                            notice: TaskTransferNotice?) {
        guard taskTransfers.pending[command.sessionId]?.requestId == command.requestId else { return }
        taskTransfers.pending[command.sessionId] = nil
        let expected = (sessions + sessionHistory).first { $0.sessionId == command.sessionId }?.transfer
        let sameDestination: Bool
        if expected?.isPending == true {
            sameDestination = notice?.queuedAt == expected?.queuedAt
                && (notice?.isPending != true || notice?.targetComputerId == expected?.targetComputerId)
        } else {
            sameDestination = notice?.targetSessionId == expected?.targetSessionId
                && notice?.acceptedAt == expected?.acceptedAt
        }
        guard accepted, let notice, notice.sourceSessionId == command.sessionId,
              notice.projectId == command.projectId, notice.taskId == command.taskId,
              notice.capsuleHash == command.capsuleHash, expected?.capsuleHash == command.capsuleHash,
              sameDestination, notice.isWellFormed, let continuedAt = notice.continuedAt,
              continuedAt > notice.confirmationTime else {
            taskTransfers.errors[command.sessionId] = L("The computer has not confirmed continuation. Check the connection and retry.")
            return
        }
        taskTransfers.confirmed[command.sessionId] = notice
        taskTransfers.errors[command.sessionId] = nil
    }
}
