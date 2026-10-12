import XCTest
@testable import GrantTap

@MainActor
final class AccountDeviceRosterTests: XCTestCase {
    private let session = GrantTapAccountSession(
        accountId: "test-account", token: String(repeating: "t", count: 43))

    func testRefreshFindsMacRegisteredAfterFirstEmptyResult() async {
        var machines: [AccountComputer] = []
        let roster = AccountDeviceRoster(load: { _ in machines })
        await roster.refresh(session: session, currentSession: { self.session })
        XCTAssertTrue(roster.computers.isEmpty)

        machines = [AccountComputer(id: "mac-id", name: "Office Mac",
                                    createdAt: 1, lastSeenAt: 2)]
        await roster.refresh(session: session, currentSession: { self.session })
        XCTAssertEqual(roster.computers.map(\.name), ["Office Mac"])
    }

    func testTransientFailureKeepsKnownDevicesAndCanRetry() async {
        var shouldFail = false
        let mac = AccountComputer(id: "mac-id", name: "Office Mac",
                                  createdAt: 1, lastSeenAt: 2)
        let roster = AccountDeviceRoster(load: { _ in
            if shouldFail { throw AccountBridgeError.unavailable }
            return [mac]
        })
        await roster.refresh(session: session, currentSession: { self.session })
        shouldFail = true
        await roster.refresh(session: session, currentSession: { self.session })
        XCTAssertEqual(roster.computers.map(\.id), ["mac-id"])
        XCTAssertNotNil(roster.error)

        shouldFail = false
        await roster.refresh(session: session, currentSession: { self.session })
        XCTAssertEqual(roster.computers.map(\.id), ["mac-id"])
        XCTAssertNil(roster.error)
    }

    func testSwitchingAccountsHidesThePreviousAccountsDevices() async {
        let other = GrantTapAccountSession(
            accountId: "other-account", token: String(repeating: "u", count: 43))
        var active = session
        var machines = [AccountComputer(id: "mac-id", name: "Old Mac",
                                        createdAt: 1, lastSeenAt: 2)]
        let roster = AccountDeviceRoster(load: { _ in machines })
        await roster.refresh(session: session, currentSession: { active })
        XCTAssertEqual(roster.computers.count, 1)

        active = other
        machines = []
        await roster.refresh(session: other, currentSession: { active })
        XCTAssertTrue(roster.computers.isEmpty)
    }

    func testSignOutDiscardsLateDeviceResponse() async {
        var complete: CheckedContinuation<[AccountComputer], Error>?
        let roster = AccountDeviceRoster(load: { _ in
            try await withCheckedThrowingContinuation { complete = $0 }
        })
        let loading = Task {
            await roster.refresh(session: session, currentSession: { self.session })
        }
        while complete == nil { await Task.yield() }
        roster.clear()
        complete?.resume(returning: [AccountComputer(id: "mac-id", name: "Old Mac",
                                                     createdAt: 1, lastSeenAt: 2)])
        await loading.value
        XCTAssertTrue(roster.computers.isEmpty)
        XCTAssertFalse(roster.isLoading)
    }
}
