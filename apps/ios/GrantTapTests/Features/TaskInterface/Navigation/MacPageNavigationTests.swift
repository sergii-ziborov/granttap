#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class MacPageNavigationTests: XCTestCase {
    func testChatOpensItsExactMeshThroughTheMainWindowRoute() {
        let model = AppModel()
        let session = SessionInfo(sessionId: "chat", agent: "codex", projectId: "mesh",
            state: "working", startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        var opened: [(String, String)] = []
        let chat = TaskChatView(session: session, modelOverride: model,
            onOpenMesh: { opened.append(($0, $1)) })
        chat.openMesh()
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.0, "mesh")
        XCTAssertEqual(opened.first?.1, "chat")
    }

    func testLogUsesACompactPageHeader() throws {
        try assertCompactHeader(AuditLogView())
    }

    func testSettingsUsesTheSameCompactHeader() throws {
        let model = AppModel()
        try assertCompactHeader(SettingsView(modelOverride: model)
            .environmentObject(model).environmentObject(MacLocalMCPModel()))
    }

    private func assertCompactHeader<V: View>(_ view: V) throws {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let controller = UIHostingController(rootView: CompatNavigationStack { view })
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let bars = descendants(controller.view).compactMap { $0 as? UINavigationBar }
        XCTAssertTrue(bars.allSatisfy { $0.isHidden || $0.alpha == 0 })
        let header = UIHostingController(rootView: MacPageHeader(title: "Log", onBack: {}) {
            Button("Clear") {}
        })
        XCTAssertEqual(header.sizeThatFits(in: frame.size).height, 40, accuracy: 1)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
#endif
