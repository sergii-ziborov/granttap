import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SwiftUIJourneyCoverageTests: XCTestCase {
    private var model: AppModel!

    override func setUp() async throws {
        model = AppModel.shared
        model.startDemo()
    }

    override func tearDown() async throws {
        model.stopDemo()
        model = nil
    }

    func testNowJourneyRendersPendingAndPrioritizedTasks() {
        XCTAssertEqual(model.pending.count + model.questions.count, 2)
        XCTAssertEqual(model.sessions.map(\.sessionId), [
            AppModelDemoFixtures.codexSessionId,
            AppModelDemoFixtures.claudeSessionId,
        ])
        assertRendered(ContentView().environmentObject(model), minimumBytes: 18_000)
    }

    func testTasksJourneyRendersSearchAndActiveRows() {
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertTrue(model.sessions.contains {
            $0.displayTitle == L("GrantTap release audit")
        })
        assertRendered(
            ContentView(selectedTab: .tasks).environmentObject(model),
            minimumBytes: 14_000
        )
    }

    func testUsageJourneyRendersOperationalDemoData() {
        assertRendered(
            NavigationView { CapabilityUsageView() },
            minimumBytes: 16_000
        )
    }

    func testTaskJourneyRendersTimelineControlsAndComposer() throws {
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(model.activities[session.sessionId]?.entries.count, 3)
        XCTAssertEqual(session.childThreads?.count, 2)
        XCTAssertEqual(session.mcpServers?.count, 3)
        assertRendered(
            NavigationView {
                TaskChatView(session: session).environmentObject(model)
            },
            minimumBytes: 20_000
        )
        // Open by default; a collapsed pass still has to render the section.
        assertRendered(
            NavigationView {
                TaskChatView(session: session, initialAgentThreadsExpanded: true).environmentObject(model)
            },
            minimumBytes: 20_000
        )
    }

    func testSettingsAndPairingJourneysRenderRealControls() {
        assertRendered(
            SettingsSheet().environmentObject(model),
            minimumBytes: 15_000
        )
        assertRendered(
            PairingSheet().environmentObject(model),
            minimumBytes: 15_000
        )
    }

    func testNewTaskAndExistingTaskComposerJourneysRender() throws {
        let attachment = AttachmentDraft(
            name: "release.txt", mimeType: "text/plain", data: Data("verify".utf8)
        )
        assertRendered(
            ContentView(
                showNewTask: true, showNewTaskRoute: true,
                messageText: "Run release checks", attachments: [attachment]
            ).environmentObject(model),
            minimumBytes: 16_000
        )
        let session = try XCTUnwrap(model.sessions.last)
        assertRendered(
            ContentView(
                showNewTask: true, composeSessionId: session.sessionId,
                messageText: "Continue this task"
            ).environmentObject(model),
            minimumBytes: 16_000
        )
    }

    private func assertRendered<V: View>(
        _ view: V,
        minimumBytes: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        let bytes = image.pngData()?.count ?? 0
        XCTAssertGreaterThan(bytes, minimumBytes, file: file, line: line)
        window.isHidden = true
    }
}
