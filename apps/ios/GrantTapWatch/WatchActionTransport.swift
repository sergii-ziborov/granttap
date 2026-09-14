import Foundation
import WatchConnectivity

/// The watch-side delivery surface used to reach the paired iPhone.
///
/// `WCSession` supplies it in the app. Tests supply a deterministic double so
/// queueing, reachability fallback, and flush behavior are covered by real
/// assertions instead of whatever pairing state a simulator happens to have.
protocol WatchActionTransport: AnyObject {
    var isActivated: Bool { get }
    var isPhoneReachable: Bool { get }
    func activateTransport()
    func sendAction(_ message: [String: Any], onFailure: @escaping () -> Void)
    func queueAction(_ message: [String: Any])
}

extension WCSession: WatchActionTransport {
    var isActivated: Bool { activationState == .activated }
    var isPhoneReachable: Bool { isReachable }

    func activateTransport() { activate() }

    func sendAction(_ message: [String: Any], onFailure: @escaping () -> Void) {
        sendMessage(message, replyHandler: nil) { _ in onFailure() }
    }

    func queueAction(_ message: [String: Any]) { transferUserInfo(message) }
}
