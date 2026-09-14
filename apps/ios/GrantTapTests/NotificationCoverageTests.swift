import UserNotifications
import XCTest
@testable import GrantTap

final class NotificationCoverageTests: XCTestCase {
    /// iOS resolves the icon in Assets.car through this name. Without it the
    /// bundle keeps only the legacy icon-file fallback, and a Lock Screen
    /// notification shows a generic tile instead of GrantTap.
    func testTheBundleNamesItsIconSoNotificationsCanShowIt() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        XCTAssertEqual(name, "AppIcon")
    }

    func testCategoryRegistrationAndEveryAuthorizationStatus() {
        let center = StubNotificationCenter()
        let manager = NotificationManager(center: center, responseHandler: { _ in })
        manager.registerCategories()
        XCTAssertEqual(Set(center.categories.map(\.identifier)), [
            NotificationManager.categoryId,
            NotificationManager.meshDecisionCategory,
            NotificationManager.meshQuestionCategory,
        ])
        XCTAssertEqual(
            center.categories.first { $0.identifier == NotificationManager.categoryId }?.actions.count,
            2
        )
        XCTAssertNotNil(center.delegate)

        for status in [
            UNAuthorizationStatus.authorized, .provisional, .ephemeral,
        ] {
            center.status = status
            var result: Bool?
            manager.requestAuthorization { result = $0 }
            XCTAssertEqual(result, true)
        }
        center.status = .denied
        var denied: Bool?
        manager.requestAuthorization { denied = $0 }
        XCTAssertEqual(denied, false)

        center.status = .notDetermined
        center.authorizationResult = true
        var granted: Bool?
        manager.requestAuthorization { granted = $0 }
        XCTAssertEqual(granted, true)
        XCTAssertEqual(center.requestedOptions, [.alert, .sound, .badge])
        center.authorizationResult = false
        manager.requestAuthorization { granted = $0 }
        XCTAssertEqual(granted, false)
    }

    func testApprovalQuestionLocalTestPrivacyDedupeAndClear() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: NotificationPrivacy.hideDetailsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: NotificationPrivacy.hideDetailsKey)
            } else {
                defaults.removeObject(forKey: NotificationPrivacy.hideDetailsKey)
            }
        }
        let center = StubNotificationCenter()
        let manager = NotificationManager(center: center, responseHandler: { _ in })
        defaults.set(false, forKey: NotificationPrivacy.hideDetailsKey)
        let approval = request(id: "approval")
        manager.present(approval, roomId: "room")
        manager.present(approval, roomId: "room")
        XCTAssertEqual(center.requests.count, 1)
        let visible = try XCTUnwrap(center.requests.first)
        XCTAssertTrue(visible.content.title.contains("CODEX"))
        XCTAssertEqual(visible.content.body, approval.title)
        XCTAssertEqual(visible.content.userInfo["roomId"] as? String, "room")
        XCTAssertEqual(visible.content.userInfo["sessionId"] as? String, "session")

        manager.clear(approval.requestId)
        XCTAssertEqual(center.removedDelivered, [approval.requestId])
        XCTAssertEqual(center.removedPending, [approval.requestId])
        manager.present(approval)
        XCTAssertEqual(center.requests.count, 2)
        manager.clearPresentedDedupe()
        manager.present(approval)
        XCTAssertEqual(center.requests.count, 3)

        defaults.set(true, forKey: NotificationPrivacy.hideDetailsKey)
        manager.present(request(id: "private"))
        XCTAssertEqual(center.requests.last?.content.title, "GrantTap")
        XCTAssertFalse(center.requests.last?.content.body.contains("private") == true)

        manager.presentQuestion(AgentEvent(
            type: "agent.event", text: "ignored", requestId: nil,
            kind: "question", sessionId: nil, createdAt: 1
        ))
        let beforeQuestion = center.requests.count
        manager.presentQuestion(AgentEvent(
            type: "agent.event", text: "What next?", requestId: "question",
            kind: "question", sessionId: nil, createdAt: 1
        ), roomId: "room")
        XCTAssertEqual(center.requests.count, beforeQuestion + 1)
        XCTAssertEqual(center.requests.last?.content.userInfo["kind"] as? String, "question")
        XCTAssertEqual(center.requests.last?.content.title, "GrantTap")

        manager.fireLocalTest()
        XCTAssertEqual(center.requests.last?.identifier, "local-test")
        XCTAssertNotNil(center.requests.last?.trigger)
        defaults.set(false, forKey: NotificationPrivacy.hideDetailsKey)
        manager.fireLocalTest()
        XCTAssertTrue(center.requests.last?.content.title.contains("CLAUDE") == true)

        let item = HumanAttentionItem(
            id: "mesh", kind: .meshHandoff, action: .meshDecision,
            title: "Continue handoff?", detail: "Claude → Grok Bot", agent: "grok_bot",
            projectId: "project", taskId: "task"
        )
        manager.present(item, roomId: "mesh-room")
        manager.present(item, roomId: "mesh-room")
        XCTAssertEqual(center.requests.last?.content.categoryIdentifier,
                       NotificationManager.meshDecisionCategory)
        XCTAssertEqual(center.requests.last?.content.userInfo["projectId"] as? String, "project")
        manager.present(HumanAttentionItem(
            id: "mesh-question", kind: .meshQuestion, action: .meshReply,
            title: "Which branch?"
        ))
        XCTAssertEqual(center.requests.last?.content.categoryIdentifier,
                       NotificationManager.meshQuestionCategory)
    }

    func testResponseIntentAndInjectedHandlerCoverEveryAction() {
        var captured: [NotificationResponseIntent] = []
        let manager = NotificationManager(
            center: StubNotificationCenter(),
            responseHandler: { captured.append($0) }
        )
        let info: [AnyHashable: Any] = [
            "requestId": "request", "roomId": "room", "sessionId": "session",
        ]
        manager.handleResponse(actionIdentifier: NotificationManager.approveAction, userInfo: info)
        manager.handleResponse(actionIdentifier: NotificationManager.denyAction, userInfo: info)
        manager.handleResponse(actionIdentifier: NotificationManager.meshApproveAction, userInfo: info)
        manager.handleResponse(actionIdentifier: NotificationManager.meshDenyAction, userInfo: info)
        manager.handleResponse(
            actionIdentifier: NotificationManager.meshAnswerAction,
            userInfo: info, responseText: " release "
        )
        manager.handleResponse(
            actionIdentifier: NotificationManager.meshAnswerAction,
            userInfo: info, responseText: " "
        )
        manager.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info
        )
        manager.handleResponse(actionIdentifier: "unknown", userInfo: info)
        manager.handleResponse(
            actionIdentifier: NotificationManager.approveAction,
            userInfo: ["requestId": "local", "local": true]
        )
        manager.handleResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["requestId": "local", "local": true]
        )
        XCTAssertEqual(captured, [
            .decision(requestId: "request", decision: "allow",
                      roomId: "room", sessionId: "session"),
            .decision(requestId: "request", decision: "deny",
                      roomId: "room", sessionId: "session"),
            .meshDecision(eventId: "request", allow: true),
            .meshDecision(eventId: "request", allow: false),
            .meshAnswer(eventId: "request", text: "release"), .none,
            .wake(focusedRequestId: "request"), .none, .none,
            .wake(focusedRequestId: nil),
        ])
        let options = NotificationManager.foregroundPresentationOptions
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
        XCTAssertTrue(options.contains(.list))
    }

    @MainActor
    func testDefaultResponseRoutesDecisionWakeAndNoopThroughAnIsolatedModel() async {
        let model = AppModel()
        NotificationManager.performDefaultResponse(.none, model: model)
        NotificationManager.performDefaultResponse(
            .wake(focusedRequestId: "focus"), model: model
        )
        NotificationManager.performDefaultResponse(
            .decision(requestId: "decision", decision: "deny",
                      roomId: nil, sessionId: "session"),
            model: model
        )
        NotificationManager.performDefaultResponse(
            .meshDecision(eventId: "missing", allow: true), model: model
        )
        NotificationManager.performDefaultResponse(
            .meshDecision(eventId: "missing", allow: false), model: model
        )
        NotificationManager.performDefaultResponse(
            .meshAnswer(eventId: "missing", text: "answer"), model: model
        )
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(model.focusedApprovalId, "focus")
        XCTAssertTrue(model.log.contains { $0.contains("decision.send failed") })
    }

    private func request(id: String) -> ApprovalRequest {
        ApprovalRequest(
            type: "approval.request", requestId: id, agent: "codex",
            kind: "permission", tool: "Bash", title: "Approve \(id)?",
            command: "npm test", cwd: "/repo", sessionId: "session",
            risk: .medium, danger: .caution, createdAt: 1
        )
    }
}

private final class StubNotificationCenter: UserNotificationCenterServing {
    var categories = Set<UNNotificationCategory>()
    weak var delegate: UNUserNotificationCenterDelegate?
    var status: UNAuthorizationStatus = .notDetermined
    var authorizationResult = false
    var requestedOptions: UNAuthorizationOptions = []
    var requests: [UNNotificationRequest] = []
    var removedDelivered: [String] = []
    var removedPending: [String] = []

    func install(_ categories: Set<UNNotificationCategory>,
                 delegate: UNUserNotificationCenterDelegate) {
        self.categories = categories
        self.delegate = delegate
    }
    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        completion(status)
    }
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        requestedOptions = options
        completion(authorizationResult, nil)
    }
    func add(_ request: UNNotificationRequest) { requests.append(request) }
    func removeDelivered(_ identifiers: [String]) { removedDelivered = identifiers }
    func removePending(_ identifiers: [String]) { removedPending = identifiers }
}
