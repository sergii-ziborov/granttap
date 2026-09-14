import XCTest
@testable import GrantTap

final class PluralFormsTests: XCTestCase {
    override func tearDown() {
        unsetenv("GRANTTAP_TEST_LANGUAGE")
        super.tearDown()
    }

    func testEnglishHasOneAndMany() {
        setenv("GRANTTAP_TEST_LANGUAGE", "en", 1)
        XCTAssertEqual(LPlural(1, one: "%d process", many: "%d processes"), "1 process")
        XCTAssertEqual(LPlural(0, one: "%d process", many: "%d processes"), "0 processes")
        XCTAssertEqual(LPlural(33, one: "%d chat", many: "%d chats"), "33 chats")
    }

    func testRussianCountsTheWayRussianDoes() {
        setenv("GRANTTAP_TEST_LANGUAGE", "ru", 1)
        let forms = [
            1: "1 процесс", 2: "2 процесса", 4: "4 процесса", 5: "5 процессов", 11: "11 процессов",
            12: "12 процессов", 21: "21 процесс", 22: "22 процесса", 100: "100 процессов",
        ]
        for (count, expected) in forms {
            XCTAssertEqual(LPlural(count, one: "%d process", many: "%d processes"), expected)
        }
        XCTAssertEqual(LPlural(3, one: "%d chat", many: "%d chats"), "3 чата")
    }

    func testProcessKindShareFallsBackToMemoryWhenIdle() {
        let busy = [
            ProcessGroupLoad(name: "node", count: 19, cpuPercent: 60, memoryBytes: 5e8),
            ProcessGroupLoad(name: "zsh", count: 3, cpuPercent: 20, memoryBytes: 1e6),
        ]
        XCTAssertEqual(AgentLoadDetailView.share(of: busy[0], among: busy), 0.75, accuracy: 0.001)
        let idle = [
            ProcessGroupLoad(name: "claude", count: 6, cpuPercent: 0, memoryBytes: 3e8),
            ProcessGroupLoad(name: "zsh", count: 3, cpuPercent: 0, memoryBytes: 1e8),
        ]
        XCTAssertEqual(AgentLoadDetailView.share(of: idle[0], among: idle), 0.75, accuracy: 0.001)
        XCTAssertEqual(AgentLoadDetailView.share(of: idle[0], among: []), 0)
    }
}
