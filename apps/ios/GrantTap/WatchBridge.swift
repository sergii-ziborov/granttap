import Foundation
import WatchConnectivity

protocol WatchSessionTransport: AnyObject {
    var activationState: WCSessionActivationState { get }
    func install(delegate: WCSessionDelegate)
    func activate()
    func updateApplicationContext(_ context: [String: Any]) throws
}

extension WCSession: WatchSessionTransport {
    func install(delegate: WCSessionDelegate) { self.delegate = delegate }
}

/// Phone side of the watch link. Mirrors the current approvals + sessions to the
/// watch, and receives decisions/replies from it, handing them to AppModel
/// (which owns the relay connection).
@MainActor
final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchBridge(transport: systemTransport(), model: .shared)

    private var latest = WatchState()
    private var delivered: WatchState?
    private let transport: WatchSessionTransport?
    private let model: AppModel

    init(transport: WatchSessionTransport?, model: AppModel) {
        self.transport = transport
        self.model = model
        super.init()
    }

    private static func systemTransport() -> WatchSessionTransport? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    static func hasSameMeaningfulState(_ lhs: WatchState, _ rhs: WatchState) -> Bool {
        lhs.attention == rhs.attention
            && lhs.approvals == rhs.approvals
            && lhs.questions == rhs.questions
            && lhs.sessions == rhs.sessions
            && lhs.activities == rhs.activities
            && lhs.agents == rhs.agents
            && lhs.connected == rhs.connected
            && lhs.machine == rhs.machine
    }

    func start() {
        guard let transport else { return }
        transport.install(delegate: self)
        transport.activate()
    }

    /// Push the latest snapshot to the watch. Cheap to call often — we skip if
    /// nothing meaningful changed.
    func push(_ state: WatchState, force: Bool = false) {
        guard let transport else { return }
        var next = state
        next.stamp = Date().timeIntervalSince1970
        latest = next
        if !force, let delivered,
           Self.hasSameMeaningfulState(next, delivered) { return }
        guard transport.activationState == .activated else { return }
        if let data = try? JSONEncoder().encode(next) {
            do {
                try transport.updateApplicationContext(["state": data])
                delivered = next
            } catch {
                // Keep `latest` so activation or a refresh request can retry.
            }
        }
    }

    private func resendLatest() {
        push(latest, force: true)
    }

    // MARK: incoming from watch

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    private nonisolated func handle(_ message: [String: Any]) {
        guard let data = message["action"] as? Data,
              let action = try? JSONDecoder().decode(WatchAction.self, from: data) else { return }
        Task { @MainActor in
            switch action.kind {
            case .decision:
                if let id = action.requestId, let d = action.decision {
                    model.decideById(id, d, by: action.by,
                                     sessionId: action.sessionId)
                }
            case .message:
                if let text = action.text, !text.isEmpty {
                    model.sendMessage(text, agent: action.agent,
                                      sessionId: action.sessionId,
                                      requestId: action.requestId)
                }
            case .meshDecision:
                guard let eventId = action.requestId else { return }
                if action.decision == "allow" {
                    model.authorizeMeshEvent(eventId)
                } else if action.decision == "deny" {
                    model.dismissMeshEvent(eventId)
                }
            case .meshAnswer:
                if let eventId = action.requestId, let text = action.text {
                    model.answerMeshQuestion(eventId, text: text)
                }
            case .subscription:
                if let id = action.sessionId, let active = action.active {
                    let source = String((action.source ?? "detail").prefix(32))
                    model.subscribeSession(id, active: active,
                                           source: "watch:\(source):\(id)")
                }
            case .refresh:
                model.pushToWatch(force: true)
            }
        }
    }

    // MARK: WCSessionDelegate lifecycle

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.resendLatest() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.transport?.activate() }
    }
}
