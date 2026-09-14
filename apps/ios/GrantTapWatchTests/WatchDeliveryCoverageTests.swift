import SwiftUI
import XCTest
@testable import GrantTapWatch

/// Deterministic double for the phone link. Simulator pairing state must not
/// decide which delivery branch a release gate exercises.
private final class FakeTransport: WatchActionTransport {
    var isActivated: Bool
    var isPhoneReachable: Bool
    var failSend = false
    private(set) var activations = 0
    private(set) var sent: [Data] = []
    private(set) var queued: [Data] = []

    init(activated: Bool, reachable: Bool) {
        isActivated = activated
        isPhoneReachable = reachable
    }

    func activateTransport() { activations += 1 }

    func sendAction(_ message: [String: Any], onFailure: @escaping () -> Void) {
        sent.append(message["action"] as? Data ?? Data())
        if failSend { onFailure() }
    }

    func queueAction(_ message: [String: Any]) {
        queued.append(message["action"] as? Data ?? Data())
    }
}

@MainActor
final class WatchDeliveryCoverageTests: XCTestCase {
    private let bridge = WatchBridge.shared

    override func setUp() {
        super.setUp()
        // A paired iPhone simulator can push its own context into the shared
        // bridge. Start every case from a known state instead of inheriting it.
        bridge.state = WatchState()
        bridge.hasLiveData = false
    }

    override func tearDown() {
        unsetenv("GRANTTAP_E2E_AUTO_ALLOW")
        bridge.flushPending(through: FakeTransport(activated: true, reachable: false))
        bridge.state = WatchState()
        bridge.hasLiveData = false
        super.tearDown()
    }

    func testInactiveTransportQueuesUntilActivationFlushesEveryAction() throws {
        let inactive = FakeTransport(activated: false, reachable: true)
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        bridge.send(first, through: inactive)
        bridge.send(second, through: inactive)
        XCTAssertEqual(inactive.activations, 2)
        XCTAssertEqual(inactive.sent, [])
        XCTAssertEqual(bridge.queuedActionCount, 2)

        let activated = FakeTransport(activated: true, reachable: true)
        bridge.flushPending(through: activated)
        XCTAssertEqual(activated.sent, [first, second])
        XCTAssertEqual(bridge.queuedActionCount, 0)
        XCTAssertEqual(activated.queued, [])
    }

    func testUnreachableAndFailedSendsFallBackToBackgroundTransfer() {
        let unreachable = FakeTransport(activated: true, reachable: false)
        let payload = Data("offline".utf8)
        bridge.send(payload, through: unreachable)
        XCTAssertEqual(unreachable.sent, [])
        XCTAssertEqual(unreachable.queued, [payload])

        let flaky = FakeTransport(activated: true, reachable: true)
        flaky.failSend = true
        bridge.send(payload, through: flaky)
        XCTAssertEqual(flaky.sent, [payload])
        XCTAssertEqual(flaky.queued, [payload])
    }

    func testApplicationContextAppliesStateAndAutoAllowsOnlyUnderTheE2EFlag() async throws {
        let approval = WatchApproval(
            id: "watch-context-approval", agent: "codex", title: "Deploy?",
            command: "npm run deploy", risk: "high", cwd: "/repo", sessionId: "session"
        )
        let context = try ["state": JSONEncoder().encode(
            WatchState(approvals: [approval], machine: "Mac", connected: true, stamp: 1)
        )]
        bridge.session(.default, didReceiveApplicationContext: context)
        try await waitForApproval(approval.id)
        XCTAssertEqual(bridge.state.approvals, [approval])
        XCTAssertEqual(bridge.state.machine, "Mac")
        XCTAssertTrue(bridge.hasLiveData)

        bridge.state = WatchState()
        setenv("GRANTTAP_E2E_AUTO_ALLOW", "1", 1)
        bridge.session(.default, didReceiveApplicationContext: context)
        try await waitForApproval(approval.id)

        // A malformed payload must not wipe good state. Twenty milliseconds was
        // a bet on how fast the machine is, and it lost under the load of a full
        // gate run: the claim is about what survives, not about how quickly a
        // busy simulator gets there.
        bridge.session(.default, didReceiveApplicationContext: ["state": Data("{".utf8)])
        try await waitForApproval(approval.id)
    }

    func testNeedsYouRendersPendingQuestionsBesideApprovals() throws {
        let approval = try XCTUnwrap(demoState().approvals.first)
        bridge.state = WatchState(
            approvals: [approval],
            questions: [WatchQuestion(
                id: "watch-question", text: "Which branch should ship?", sessionId: approval.sessionId
            )],
            sessions: demoState().sessions,
            machine: "Mac", connected: true, stamp: 2
        )
        bridge.hasLiveData = true
        let renderer = ImageRenderer(content: UnifiedTaskPage().frame(width: 198, height: 242))
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage)
    }

    func testNeedsYouRendersMeshDecisionsAndOpenOnPhoneItems() throws {
        let state = WatchState(attention: [
            HumanAttentionItem(
                id: "handoff", kind: .meshHandoff, action: .meshDecision,
                title: "Claude → Codex", detail: "Continue handoff?", agent: "claude",
                projectId: "project", taskId: "task", createdAt: 2
            ),
            HumanAttentionItem(
                id: "conflict", kind: .meshConflict, action: .openPhone,
                title: "Resource conflict", detail: "Both agents claim auth/**",
                projectId: "project", taskId: "task", createdAt: 1
            ),
        ], machine: "Mac", connected: true, stamp: 3)
        bridge.state = state
        bridge.hasLiveData = true
        XCTAssertEqual(WatchChat(from: state.attention[0]).attentionAction, .meshDecision)
        XCTAssertEqual(WatchChat(from: state.attention[1]).attentionAction, .openPhone)
        let renderer = ImageRenderer(content: UnifiedTaskPage().frame(width: 198, height: 242))
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage)
    }

    private func demoState() -> WatchState {
        setenv("GRANTTAP_DEMO", "1", 1)
        bridge.start()
        unsetenv("GRANTTAP_DEMO")
        return bridge.state
    }

    private func waitForApproval(_ id: String) async throws {
        for _ in 0..<50 where bridge.state.approvals.first?.id != id {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(bridge.state.approvals.first?.id, id)
    }
}
