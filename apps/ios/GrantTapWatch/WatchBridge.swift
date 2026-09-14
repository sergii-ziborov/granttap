import Foundation
import WatchConnectivity

/// Watch side of the link. Receives the mirrored state from the phone and sends
/// decisions/replies back. The phone owns the relay; the watch just reflects it.
@MainActor
final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchBridge()

    @Published var state = WatchState()
    /// True once the phone has ever sent us a snapshot.
    @Published var hasLiveData = false
    @Published var linkActive = false
    @Published var phoneReachable = false
    private var pendingActions: [Data] = []
#if DEBUG
    private var e2eAutoDecided = Set<String>()
#endif

    func start() {
#if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1" {
            seedDeterministicDemo()
            return
        }
#endif
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        linkActive = s.activationState == .activated
        phoneReachable = s.isReachable
        apply(s.receivedApplicationContext) // pick up whatever the phone pushed while asleep
        if linkActive { requestRefresh() }
    }

#if DEBUG
    private func deterministicDemoApproval(sessionId: String) -> WatchApproval {
        WatchApproval(
            id: "watch-approval-demo",
            agent: "codex",
            title: L("Run the GrantTap release checks?"),
            command: "npm test && npm run typecheck",
            risk: "high",
            cwd: "/Users/reviewer/granttap",
            sessionId: sessionId
        )
    }

    /// A native, deterministic state for documentation and UI regression
    /// captures. Release builds always wait for the paired iPhone instead.
    private func seedDeterministicDemo() {
        let now = Date().timeIntervalSince1970 * 1_000
        let codexId = "watch-codex-demo"
        let claudeId = "watch-claude-demo"
        state = WatchState(
            approvals: [deterministicDemoApproval(sessionId: codexId)],
            sessions: [
                WatchSession(
                    id: codexId,
                    agent: "codex",
                    title: L("GrantTap release audit"),
                    state: "working",
                    tokensSession: 18_420,
                    tokensLastTurn: 1_284,
                    elapsedSec: 12 * 60,
                    contextTokensUsed: 103_600,
                    contextWindow: 258_400
                ),
                WatchSession(
                    id: claudeId,
                    agent: "claude",
                    title: L("Review zero-knowledge relay"),
                    state: "waiting",
                    tokensSession: 26_780,
                    tokensLastTurn: 2_146,
                    elapsedSec: 34 * 60,
                    contextTokensUsed: 71_200,
                    contextWindow: 200_000
                ),
                WatchSession(
                    id: "watch-recent-demo",
                    agent: "codex",
                    title: L("Verify App Store metadata"),
                    state: "idle",
                    tokensSession: 9_840,
                    tokensLastTurn: 930,
                    elapsedSec: 8 * 60,
                    contextTokensUsed: 42_100,
                    contextWindow: 258_400
                ),
            ],
            activities: [
                WatchActivity(
                    sessionId: codexId,
                    agent: "codex",
                    state: "working",
                    entries: [
                        WatchActivityEntry(
                            id: "watch-message-demo",
                            kind: "message",
                            text: L("Checking the package, screenshots, and release metadata."),
                            createdAt: now - 45_000
                        ),
                        WatchActivityEntry(
                            id: "watch-tool-demo",
                            kind: "tool",
                            text: "npm test && npm run typecheck",
                            createdAt: now - 25_000
                        ),
                        WatchActivityEntry(
                            id: "watch-final-demo",
                            kind: "final",
                            text: L("The package is ready for approval."),
                            createdAt: now - 5_000
                        ),
                    ]
                ),
                WatchActivity(
                    sessionId: claudeId,
                    agent: "claude",
                    state: "waiting",
                    entries: [
                        WatchActivityEntry(
                            id: "watch-claude-message-demo",
                            kind: "message",
                            text: L("Tracing task-key isolation and delivery receipts."),
                            createdAt: now - 150_000
                        ),
                        WatchActivityEntry(
                            id: "watch-claude-final-demo",
                            kind: "final",
                            text: L("The relay only receives opaque ciphertext."),
                            createdAt: now - 120_000
                        ),
                    ]
                ),
            ],
            agents: [
                WatchAgentIntegration(agent: "codex", installed: true, hookConfigured: true),
                WatchAgentIntegration(agent: "claude", installed: true, hookConfigured: true),
            ],
            machine: "Demo Mac",
            connected: true,
            stamp: now
        )
        hasLiveData = true
        linkActive = true
        phoneReachable = true
    }
#endif

    func requestRefresh() {
        send(.refresh())
    }

    func send(_ action: WatchAction) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(action) else { return }
        send(data, through: WCSession.default)
    }

    func send(_ data: Data, through transport: WatchActionTransport) {
        guard transport.isActivated else {
            pendingActions.append(data)
            transport.activateTransport()
            return
        }
        deliver(data, through: transport)
    }

    func deliver(_ data: Data, through transport: WatchActionTransport) {
        let message = ["action": data]
        guard transport.isPhoneReachable else {
            transport.queueAction(message)
            return
        }
        transport.sendAction(message) {
            // Reachability can change between the check and send. Queue a
            // background transfer instead of silently dropping the action.
            transport.queueAction(message)
        }
    }

    func flushPending(through transport: WatchActionTransport) {
        let queued = pendingActions
        pendingActions.removeAll()
        for data in queued {
            deliver(data, through: transport)
        }
    }

    var queuedActionCount: Int { pendingActions.count }

    // MARK: incoming state

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["state"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchState.self, from: data) else { return }
        state = decoded
        hasLiveData = true
#if DEBUG
        // Simulator-only round-trip seam. Release builds cannot auto-approve,
        // and Debug builds do so only when launched with the explicit E2E flag.
        if ProcessInfo.processInfo.environment["GRANTTAP_E2E_AUTO_ALLOW"] == "1",
           let approval = decoded.approvals.first,
           !e2eAutoDecided.contains(approval.id) {
            e2eAutoDecided.insert(approval.id)
            send(.decision(approval.id, "allow", sessionId: approval.sessionId))
        }
#endif
    }

    // MARK: lifecycle

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.linkActive = activationState == .activated
            self.phoneReachable = session.isReachable
            self.apply(session.receivedApplicationContext)
            if activationState == .activated {
                self.flushPending(through: session)
                self.requestRefresh()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.phoneReachable = session.isReachable
            if session.isReachable { self.requestRefresh() }
        }
    }
}
