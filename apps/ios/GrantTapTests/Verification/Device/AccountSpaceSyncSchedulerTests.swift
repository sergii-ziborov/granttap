import XCTest
@testable import GrantTap

final class AccountSpaceSyncSchedulerTests: XCTestCase {
    @MainActor
    func testFailedRecoveryIsVisibleAndExplicitRetryClearsTheFailure() async {
        let model = AppModel()
        let session = GrantTapAccountSession(accountId: "account", token: "test-token")
        model.scheduleAccountSpaceSync(session: session, now: 1_000) { _, _ in
            throw AccountBridgeError.recoveryFailed
        }
        let first = model.accountSpaceSyncTask
        await first?.value
        XCTAssertEqual(model.accountSpaceSyncError,
                       AccountBridgeError.recoveryFailed.localizedDescription)

        var retryCount = 0
        model.scheduleAccountSpaceSync(session: session, force: true, now: 1_001) { _, _ in
            retryCount += 1
        }
        XCTAssertNil(model.accountSpaceSyncError)
        let second = model.accountSpaceSyncTask
        await second?.value
        XCTAssertEqual(retryCount, 1)
        XCTAssertNil(model.accountSpaceSyncError)
        XCTAssertNil(model.accountSpaceSyncTask)
    }

    @MainActor
    func testThrottleSkipsAutomaticRetryButForcedRepairRunsForItsRoom() async {
        let model = AppModel()
        let session = GrantTapAccountSession(accountId: "account", token: "test-token")
        var repairedRooms: [String?] = []
        model.scheduleAccountSpaceSync(session: session, now: 1_000) { _, room in
            repairedRooms.append(room)
        }
        let first = model.accountSpaceSyncTask
        await first?.value

        model.scheduleAccountSpaceSync(session: session, now: 1_001) { _, room in
            repairedRooms.append(room)
        }
        XCTAssertNil(model.accountSpaceSyncTask)
        model.scheduleAccountSpaceSync(session: session, force: true,
                                       repairRoomId: "mac-room", now: 1_001) { _, room in
            repairedRooms.append(room)
        }
        let forced = model.accountSpaceSyncTask
        await forced?.value
        XCTAssertEqual(repairedRooms.count, 2)
        XCTAssertEqual(repairedRooms.last!, "mac-room")
    }

    @MainActor
    func testForcedRetryCannotBeOverwrittenByAnOlderCancelledAttempt() async {
        let model = AppModel()
        let session = GrantTapAccountSession(accountId: "account", token: "test-token")
        let started = expectation(description: "first recovery started")
        model.scheduleAccountSpaceSync(session: session, now: 1_000) { _, _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        let oldTask = model.accountSpaceSyncTask
        await fulfillment(of: [started], timeout: 2)

        model.scheduleAccountSpaceSync(session: session, force: true, now: 1_001) { _, _ in
            throw AccountBridgeError.recoveryFailed
        }
        let newTask = model.accountSpaceSyncTask
        await newTask?.value
        await oldTask?.value
        XCTAssertEqual(model.accountSpaceSyncError,
                       AccountBridgeError.recoveryFailed.localizedDescription)
        XCTAssertNil(model.accountSpaceSyncTask)
    }

    @MainActor
    func testStoppingRecoveryClearsThePendingTask() async {
        let model = AppModel()
        let session = GrantTapAccountSession(accountId: "account", token: "test-token")
        let started = expectation(description: "recovery started")
        model.scheduleAccountSpaceSync(session: session, now: 1_000) { _, _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        let running = model.accountSpaceSyncTask
        await fulfillment(of: [started], timeout: 2)
        model.stopAccountSpaceSync()
        await running?.value
        XCTAssertNil(model.accountSpaceSyncTask)
        XCTAssertNil(model.accountSpaceSyncGeneration)
    }
}
