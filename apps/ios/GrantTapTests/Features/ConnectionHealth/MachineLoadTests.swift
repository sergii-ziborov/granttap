import XCTest
@testable import GrantTap

/// The load screen exists to answer "which agent is making my Mac hot?", so its
/// numbers must stay separately measured and must never invent a value.
final class MachineLoadTests: XCTestCase {
    private func load(_ agents: [AgentLoadSample]) -> MachineLoad {
        MachineLoad(
            machine: "test.local",
            monitorCpuPercent: 0.6,
            monitorMemoryBytes: 570_000_000,
            agents: agents,
            generatedAt: 1
        )
    }

    func testCpuShareIsRelativeToMeasuredAgentCpuOnly() {
        let model = load([
            AgentLoadSample(agent: "codex", cpuPercent: 90),
            AgentLoadSample(agent: "claude", cpuPercent: 30),
        ])
        let codex = model.agents[0]
        XCTAssertEqual(model.cpuShare(of: codex) ?? 0, 0.75, accuracy: 0.0001)
    }

    func testCpuShareIsNilWhenNothingIsRunning() {
        let model = load([AgentLoadSample(agent: "claude", scanMs: 1_200)])
        XCTAssertNil(
            model.cpuShare(of: model.agents[0]),
            "a zero denominator must not render as a confident 0%"
        )
        XCTAssertNil(ConnectionLoadFormat.share(nil))
    }

    func testAnAgentWithNoProcessStillReportsItsScanCost() {
        let sample = AgentLoadSample(agent: "codex", sessions: 152, scanMs: 8_400)
        XCTAssertEqual(ConnectionLoadFormat.cpu(sample.cpuPercent), "—")
        XCTAssertEqual(ConnectionLoadFormat.duration(ms: sample.scanMs), "8.4s")
    }

    func testFormattersNeverShowAFabricatedZero() {
        XCTAssertEqual(ConnectionLoadFormat.bytes(0), "—")
        XCTAssertEqual(ConnectionLoadFormat.tokens(0), "—")
        XCTAssertEqual(ConnectionLoadFormat.duration(ms: 0), "—")
        XCTAssertEqual(ConnectionLoadFormat.cpu(0), "—")
    }

    func testHumanReadableMagnitudes() {
        XCTAssertEqual(ConnectionLoadFormat.bytes(1_048_576), "1.0 MB")
        XCTAssertEqual(ConnectionLoadFormat.bytes(570_000_000), "544 MB")
        XCTAssertEqual(ConnectionLoadFormat.tokens(825_000_000), "825.0M")
        XCTAssertEqual(ConnectionLoadFormat.tokens(1_500), "2k")
        XCTAssertEqual(ConnectionLoadFormat.duration(ms: 420), "420ms")
    }

    func testCatalogAgeFallsBackToNeverRatherThanZero() {
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: nil), "never")
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: 42), "42s ago")
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: 300), "5m ago")
        XCTAssertEqual(ConnectionLoadFormat.age(seconds: 7_200), "2h ago")
    }

    func testDecodesAWireLoadPayloadWithMissingOptionalFields() throws {
        let json = """
        {"type":"machine.load","machine":"m","monitorCpuPercent":1.5,
         "monitorMemoryBytes":100,"generatedAt":9,
         "agents":[{"agent":"grok","processes":1,"cpuPercent":2,"memoryBytes":3,
                    "sessions":4,"scanMs":5,"tokensRecent":6}]}
        """
        let decoded = try JSONDecoder().decode(MachineLoad.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.agents.count, 1)
        XCTAssertEqual(decoded.agents[0].agent, "grok")
        XCTAssertNil(decoded.agents[0].contextTokens)
        XCTAssertEqual(decoded.monitorCpuPercent, 1.5)
    }
}
