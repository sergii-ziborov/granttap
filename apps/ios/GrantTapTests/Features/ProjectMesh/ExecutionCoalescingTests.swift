import XCTest
@testable import GrantTap

final class ExecutionCoalescingTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private func link(_ computer: String, session: String = "s1", startedAt: Double, activeAt: Double? = nil,
                      updatedAt: Double? = nil, endedAt: Double? = nil, branch: String? = nil) -> ExecutionSessionLink {
        ExecutionSessionLink(taskId: "t", sessionId: session, provider: "claude", computerId: computer, workspace: "/repo",
                             branch: branch, updatedAt: updatedAt, activeAt: activeAt, startedAt: startedAt, endedAt: endedAt)
    }

    func testTheSameChatUnderTwoNamesOfOneComputerIsOneExecution() {
        let retired = link("Serhiis-MacBook-Pro.local", startedAt: now - 5 * 86_400_000, updatedAt: now - 86_400_000,
                           endedAt: now - 86_400_000, branch: "main")
        let live = link("Mac.lan", startedAt: now - 4 * 86_400_000, activeAt: now - 60_000, updatedAt: now - 30_000)
        let merged = ExecutionCoalescing.coalesced([retired, live])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].computerId, "Mac.lan", "the live name is the computer's name")
        XCTAssertEqual(merged[0].startedAt, now - 5 * 86_400_000, "the earliest start")
        XCTAssertNil(merged[0].endedAt, "open while any row is open")
        XCTAssertEqual(merged[0].lastSeenAt, now - 60_000)
        XCTAssertEqual(merged[0].branch, "main", "facts the live row lacks come from the other")
        XCTAssertEqual(merged[0].updatedAt, now - 30_000)
    }

    func testEveryRowOverMeansOverAndDifferentChatsStayApart() {
        let a = link("Mac.lan", startedAt: 1, endedAt: 10)
        let b = link("Serhiis-MacBook-Pro.local", startedAt: 2, endedAt: 30)
        let merged = ExecutionCoalescing.merge([a, b])
        XCTAssertEqual(merged.endedAt, 30)
        XCTAssertEqual(merged.computerId, "Serhiis-MacBook-Pro.local", "the freshest row names the computer when all are over")
        let other = link("Mac.lan", session: "s2", startedAt: 3)
        let all = ExecutionCoalescing.coalesced([a, other, b])
        XCTAssertEqual(all.map(\.sessionId), ["s1", "s2"], "order of first appearance, one row per chat")
        XCTAssertEqual(ExecutionCoalescing.coalesced([]).count, 0)
        XCTAssertEqual(ExecutionCoalescing.coalesced([other])[0], other, "a lone row is itself")
    }
}
