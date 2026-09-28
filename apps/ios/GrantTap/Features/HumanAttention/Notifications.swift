import Foundation
import UserNotifications

protocol UserNotificationCenterServing: AnyObject {
    func install(_ categories: Set<UNNotificationCategory>,
                 delegate: UNUserNotificationCenterDelegate)
    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Bool, Error?) -> Void
    )
    func add(_ request: UNNotificationRequest)
    func removeDelivered(_ identifiers: [String])
    func removePending(_ identifiers: [String])
}

private final class SystemUserNotificationCenter: UserNotificationCenterServing {
    private let center = UNUserNotificationCenter.current()

    func install(_ categories: Set<UNNotificationCategory>,
                 delegate: UNUserNotificationCenterDelegate) {
        center.setNotificationCategories(categories)
        center.delegate = delegate
    }

    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { completion($0.authorizationStatus) }
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        center.requestAuthorization(options: options, completionHandler: completion)
    }

    func add(_ request: UNNotificationRequest) { center.add(request) }
    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

enum NotificationResponseIntent: Equatable {
    case decision(requestId: String, decision: String, roomId: String?, sessionId: String?)
    case meshDecision(eventId: String, allow: Bool)
    case meshAnswer(eventId: String, text: String)
    case wake(focusedRequestId: String?)
    case none
}

/// Actionable-notification plumbing — the heart of the "approve from your wrist"
/// feature. The category and its Approve/Deny actions are registered on iOS;
/// the system automatically forwards (mirrors) them to a paired Apple Watch, so
/// NO watchOS target is required for the buttons to appear on the watch.
///
/// Tapping an action wakes the app in the background at `didReceive`, where we
/// send the decision back through the relay.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let categoryId = "GRANTTAP_APPROVAL"
    static let approveAction = "GRANTTAP_APPROVE"
    static let denyAction = "GRANTTAP_DENY"

    let center: UserNotificationCenterServing
    private let responseHandler: (NotificationResponseIntent) -> Void

    init(
        center: UserNotificationCenterServing? = nil,
        responseHandler: ((NotificationResponseIntent) -> Void)? = nil
    ) {
        self.center = center ?? SystemUserNotificationCenter()
        self.responseHandler = responseHandler ?? { Self.performDefaultResponse($0) }
    }

    func registerCategories() {
        let approve = UNNotificationAction(
            identifier: Self.approveAction,
            title: L("Allow"),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill"))
        let deny = UNNotificationAction(
            identifier: Self.denyAction,
            title: L("Deny"),
            options: [.destructive, .authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "xmark.circle.fill"))
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [approve, deny],
            intentIdentifiers: [],
            options: [.customDismissAction])
        center.install(Set([category]).union(Self.humanAttentionCategories), delegate: self)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        center.authorizationStatus { status in
            switch status {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    /// PING_DEDUPE — at most one banner/sound per exact requestId.
    var presentedIds = Set<String>()

    /// Present an approval as an actionable, time-sensitive notification.
    func present(_ req: ApprovalRequest, roomId: String? = nil) {
        if presentedIds.contains(req.requestId) { return }
        presentedIds.insert(req.requestId)

        let content = UNMutableNotificationContent()
        if NotificationPrivacy.hidesDetails {
            content.title = "GrantTap"
            content.body = L("An agent is waiting for an authenticated decision.")
        } else {
            content.title = "\(req.agent.uppercased()) needs approval"
            content.body = req.title
        }
        content.categoryIdentifier = Self.categoryId
        content.threadIdentifier = "granttap-approvals"
        content.targetContentIdentifier = req.requestId
        var userInfo: [String: Any] = ["requestId": req.requestId]
        if let roomId, !roomId.isEmpty { userInfo["roomId"] = roomId }
        if let sessionId = req.sessionId { userInfo["sessionId"] = sessionId }
        content.userInfo = userInfo
        // .timeSensitive needs the Time Sensitive Notifications entitlement (see
        // GrantTap.entitlements) AND the matching capability on the App ID — without
        // both, iOS silently downgrades to .active and Focus swallows the alert.
        // .critical needs Apple's separately-approved Critical Alerts entitlement.
        content.interruptionLevel = .timeSensitive
        content.sound = .default

        let request = UNNotificationRequest(identifier: req.requestId, content: content, trigger: nil)
        center.add(request)
    }

    /// MCP open ask / question events — banner even when the app is backgrounded.
    func presentQuestion(_ event: AgentEvent, roomId: String? = nil) {
        guard let requestId = event.requestId else { return }
        let content = UNMutableNotificationContent()
        if NotificationPrivacy.hidesDetails {
            content.title = "GrantTap"
            content.body = L("An agent is waiting for your answer.")
        } else {
            content.title = "GrantTap question"
            content.body = event.text
        }
        content.threadIdentifier = "granttap-questions"
        content.targetContentIdentifier = requestId
        var userInfo: [String: Any] = ["requestId": requestId, "kind": "question"]
        if let roomId, !roomId.isEmpty { userInfo["roomId"] = roomId }
        content.userInfo = userInfo
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        center.add(
            UNNotificationRequest(identifier: requestId, content: content, trigger: nil))
    }

    /// Local self-test — validates that Approve/Deny mirror to the watch with NO
    /// relay and NO APNs. Fire it, lower your wrist, raise it: the buttons should
    /// appear on the watch. This de-risks the whole feature for free.
    func fireLocalTest() {
        let content = UNMutableNotificationContent()
        if NotificationPrivacy.hidesDetails {
            content.title = "GrantTap"
            content.body = L("An agent is waiting for an authenticated decision.")
        } else {
            content.title = "CLAUDE needs approval"
            content.body = "Run: rm -rf build/ && npm run release"
        }
        content.categoryIdentifier = Self.categoryId
        content.threadIdentifier = "granttap-approvals"
        content.userInfo = ["requestId": "local-test", "local": true]
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(
            UNNotificationRequest(identifier: "local-test", content: content, trigger: trigger))
    }

    func clear(_ requestId: String) {
        presentedIds.remove(requestId)
        center.removeDelivered([requestId])
        center.removePending([requestId])
    }

    /// Drop ping-dedupe state after Mac cancel-all so a later real ask can notify.
    func clearPresentedDedupe() {
        presentedIds.removeAll()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while the app is foregrounded (so you can test easily).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        // The remote push is silent and contains no task data. Only this local,
        // post-decryption notification reaches the presentation delegate.
        completionHandler(Self.foregroundPresentationOptions)
    }

    /// The action tap (from watch, lock screen, or banner).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        handleResponse(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo,
            responseText: (response as? UNTextInputNotificationResponse)?.userText
        )
        completionHandler()
    }

    static var foregroundPresentationOptions: UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func handleResponse(actionIdentifier: String, userInfo: [AnyHashable: Any],
                        responseText: String? = nil) {
        responseHandler(Self.responseIntent(
            actionIdentifier: actionIdentifier, userInfo: userInfo, responseText: responseText
        ))
    }

    static func responseIntent(
        actionIdentifier: String, userInfo: [AnyHashable: Any], responseText: String? = nil
    ) -> NotificationResponseIntent {
        let requestId = userInfo["requestId"] as? String ?? ""
        let roomId = userInfo["roomId"] as? String
        let sessionId = userInfo["sessionId"] as? String
        let isLocal = userInfo["local"] as? Bool ?? false
        switch actionIdentifier {
        case approveAction where !isLocal:
            return .decision(requestId: requestId, decision: "allow",
                             roomId: roomId, sessionId: sessionId)
        case denyAction where !isLocal:
            return .decision(requestId: requestId, decision: "deny",
                             roomId: roomId, sessionId: sessionId)
        case meshApproveAction:
            return .meshDecision(eventId: requestId, allow: true)
        case meshDenyAction:
            return .meshDecision(eventId: requestId, allow: false)
        case meshAnswerAction:
            let answer = responseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return answer.isEmpty ? .none : .meshAnswer(eventId: requestId, text: answer)
        case UNNotificationDefaultActionIdentifier:
            return .wake(focusedRequestId: !requestId.isEmpty && !isLocal ? requestId : nil)
        default:
            return .none
        }
    }

    static func performDefaultResponse(
        _ intent: NotificationResponseIntent,
        model suppliedModel: AppModel? = nil
    ) {
        Task { @MainActor in
            let model = suppliedModel ?? AppModel.shared
            switch intent {
            case .decision(let requestId, let decision, let roomId, let sessionId):
                model.decideById(
                    requestId, decision, by: "phone-notification",
                    roomId: roomId, sessionId: sessionId
                )
            case .meshDecision(let eventId, let allow):
                if allow { model.authorizeMeshEvent(eventId) }
                else { model.dismissMeshEvent(eventId) }
            case .meshAnswer(let eventId, let text):
                model.answerMeshQuestion(eventId, text: text)
            case .wake(let focusedRequestId):
                if let focusedRequestId { model.focusedApprovalId = focusedRequestId }
                model.handleRemoteWake { _ in }
            case .none:
                break
            }
        }
    }
}
