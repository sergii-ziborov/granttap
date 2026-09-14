import Foundation
import UserNotifications

extension NotificationManager {
    static let meshDecisionCategory = "GRANTTAP_MESH_DECISION"
    static let meshQuestionCategory = "GRANTTAP_MESH_QUESTION"
    static let meshApproveAction = "GRANTTAP_MESH_APPROVE"
    static let meshDenyAction = "GRANTTAP_MESH_DENY"
    static let meshAnswerAction = "GRANTTAP_MESH_ANSWER"

    static var humanAttentionCategories: Set<UNNotificationCategory> {
        let approve = UNNotificationAction(
            identifier: meshApproveAction, title: L("Continue"),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "arrow.right.circle.fill")
        )
        let deny = UNNotificationAction(
            identifier: meshDenyAction, title: L("Decline"),
            options: [.destructive, .authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "xmark.circle.fill")
        )
        let answer = UNTextInputNotificationAction(
            identifier: meshAnswerAction, title: L("Reply"),
            options: [.authenticationRequired], textInputButtonTitle: L("Send"),
            textInputPlaceholder: L("Your answer")
        )
        return [
            UNNotificationCategory(
                identifier: meshDecisionCategory, actions: [approve, deny],
                intentIdentifiers: [], options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: meshQuestionCategory, actions: [answer],
                intentIdentifiers: [], options: [.customDismissAction]
            ),
        ]
    }

    func present(_ item: HumanAttentionItem, roomId: String? = nil) {
        guard !presentedIds.contains(item.id) else { return }
        presentedIds.insert(item.id)
        let content = UNMutableNotificationContent()
        content.title = NotificationPrivacy.hidesDetails ? "GrantTap" : item.title
        content.body = NotificationPrivacy.hidesDetails
            ? L("An agent needs your attention.")
            : (item.detail ?? attentionAgentName(item.agent))
        content.categoryIdentifier = category(for: item.action)
        content.threadIdentifier = "granttap-needs-you"
        content.targetContentIdentifier = item.id
        var userInfo: [String: Any] = ["requestId": item.id, "kind": "human-attention"]
        if let roomId, !roomId.isEmpty { userInfo["roomId"] = roomId }
        if let projectId = item.projectId { userInfo["projectId"] = projectId }
        if let taskId = item.taskId { userInfo["taskId"] = taskId }
        content.userInfo = userInfo
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
    }

    private func category(for action: HumanAttentionAction) -> String {
        switch action {
        case .meshDecision: return Self.meshDecisionCategory
        case .meshReply: return Self.meshQuestionCategory
        default: return ""
        }
    }
}

private func attentionAgentName(_ agent: String?) -> String {
    guard let agent else { return L("Open GrantTap for details.") }
    return agent == "grok_bot" ? "Grok Bot" : AgentIdentity.displayName(agent)
}
