#if DEBUG
import Foundation
import UserNotifications

enum NotificationNavigationFixture {
    @MainActor static func apply(to model: AppModel) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_NOTIFICATION_OPEN"] == "1" else { return }
        let id = "cursor-notification-fixture", room = model.connectionRegistry.preferredId
        let request = ApprovalRequest(type: "approval.request", requestId: id, agent: "cursor",
            kind: "permission", tool: "Shell", title: "Cursor notification approval fixture", command: "git status", cwd: nil,
            sessionId: model.sessions.first?.sessionId,
            risk: .low, danger: nil, createdAt: Date().timeIntervalSince1970 * 1_000)
        model.pending.removeAll { $0.requestId == id }
        Task { @MainActor [weak model] in
            NotificationManager.shared.handleResponse(actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: ["requestId": id])
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let model else { return }
            model.receive(request, fromRoom: room)
        }
    }
}
#endif
