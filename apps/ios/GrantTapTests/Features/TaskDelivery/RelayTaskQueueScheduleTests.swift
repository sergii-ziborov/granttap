import XCTest
@testable import GrantTap

final class RelayTaskQueueScheduleTests: XCTestCase {
    private let now: Double = 10_000_000

    private func row(_ id: String, createdAt: Double, state: RelayTaskJobState?,
                     immediate: Bool = false, notBefore: Double? = nil) -> OutgoingDelivery {
        var row = OutgoingDelivery(id: id, text: "Synthetic queued task", agent: "codex", cwd: nil,
            sessionId: "fixture-chat", requestId: nil, attachments: [], preferredMcp: nil, skill: nil,
            createdAt: createdAt, updatedAt: createdAt, attempts: 0,
            state: state == .failed || state == .expired ? .failed : .queued, error: nil, nextRetryAt: nil,
            chatQueue: ChatMessageQueueContext(waiting: true, transport: .relay, taskId: nil, queuedAt: createdAt,
                relayManaged: true, notBefore: notBefore ?? createdAt, sendImmediately: immediate))
        if let state {
            row.relayJob = RelayTaskQueueReservation(jobId: id, token: nil, notBefore: createdAt,
                expiresAt: createdAt + 86_400_000, createdAt: createdAt, serverState: state)
        }
        return row
    }

    func testANewMessageIsUploadedBeforeOlderReceiptChecks() {
        let rows = [row("old-receipt", createdAt: now - 60_000, state: .queued),
                    row("new-upload", createdAt: now, state: nil)]
        XCTAssertEqual(RelayTaskQueueSchedule.syncOrder(rows), ["new-upload", "old-receipt"])
    }

    func testFailedAndExpiredJobsAreNotPolledUntilThePersonActs() {
        var failed = row("failed-job", createdAt: now, state: .failed)
        XCTAssertFalse(RelayTaskQueueSchedule.needsSync(failed))
        XCTAssertFalse(RelayTaskQueueSchedule.needsSync(row("expired-job", createdAt: now, state: .expired)))
        failed.chatQueue?.cancelRequested = true
        XCTAssertTrue(RelayTaskQueueSchedule.needsSync(failed), "a retry or removal still reaches the relay")
    }

    func testAJustSavedOrRunningJobIsCheckedEverySecondAndALongWaitEveryFive() {
        XCTAssertEqual(RelayTaskQueueSchedule.delaySeconds([row("fresh", createdAt: now - 5_000, state: .queued)],
                                                           now: now), 1)
        XCTAssertEqual(RelayTaskQueueSchedule.delaySeconds([row("running", createdAt: now - 600_000, state: .accepted)],
                                                           now: now), 1)
        XCTAssertEqual(RelayTaskQueueSchedule.delaySeconds([row("waiting", createdAt: now - 600_000, state: .queued)],
                                                           now: now), 5)
        XCTAssertEqual(RelayTaskQueueSchedule.delaySeconds([row("scheduled", createdAt: now - 5_000, state: .queued,
                                                                notBefore: now + 3_600_000)], now: now), 5)
        XCTAssertEqual(RelayTaskQueueSchedule.delaySeconds([row("failed", createdAt: now, state: .failed)], now: now), 5)
    }
}
