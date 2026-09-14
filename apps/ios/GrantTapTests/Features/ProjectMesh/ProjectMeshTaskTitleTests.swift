import XCTest
@testable import GrantTap

/// The same chat must be recognisable wherever it is listed.
final class ProjectMeshTaskTitleTests: XCTestCase {
    private func task(_ title: String) -> ProjectMeshTask {
        ProjectMeshTask(
            taskId: "task", projectId: "project", title: title, goal: "Goal",
            state: "working", createdAt: 1, updatedAt: 2
        )
    }

    private func session(title: String?, cwd: String = "/Users/me/dev/nodvox") -> SessionInfo {
        SessionInfo(
            sessionId: "session", agent: "claude", title: title, cwd: cwd,
            state: "working", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
    }

    func testALiveChatIsNamedTheSameWayTheListOfLiveChatsNamesIt() {
        // This is the whole point: the Project list disagreed with the Now list
        // about the name of one chat, and the live session is the better source.
        let live = session(title: "Pairing refactor")
        XCTAssertEqual(
            ProjectMeshTaskTitle.text(task("some other published text"), session: live),
            live.displayTitle
        )
        XCTAssertEqual(ProjectMeshTaskTitle.text(task("x"), session: live), "Pairing refactor")
    }

    func testAPublishedTitleIsUsedWhenThePhoneHasNoLiveChatForIt() {
        XCTAssertEqual(
            ProjectMeshTaskTitle.text(task("Rebuild the index"), session: nil),
            "Rebuild the index"
        )
    }

    func testAParagraphIsCutToOneReadableLineRatherThanFillingTheRow() {
        let dump = """
        Fix the relay handshake so the first frame is not dropped
        It reproduces whenever the phone reconnects on cellular.
        """
        // Only the opening line is a candidate for a name.
        let shown = ProjectMeshTaskTitle.text(task(dump), session: nil)
        XCTAssertFalse(shown.contains("reproduces"))
        XCTAssertTrue(shown.hasPrefix("Fix the relay handshake"))

        let runOn = String(repeating: "word ", count: 60)
        let cut = ProjectMeshTaskTitle.presentable(runOn) ?? ""
        XCTAssertLessThanOrEqual(cut.count, ProjectMeshTaskTitle.maxLength + 1)
        XCTAssertTrue(cut.hasSuffix("…"), "a cut line says that it was cut")
    }

    func testResidueIsNotOfferedAsAName() {
        // The same shapes `displayTitle` refuses: identifiers and paths are not
        // names anyone chose, and an empty title names nothing at all.
        XCTAssertNil(ProjectMeshTaskTitle.presentable("4e69538b-cf6e-4c6c-9471-9cf5e6125442"))
        XCTAssertNil(ProjectMeshTaskTitle.presentable("/Users/me/dev/nodvox"))
        XCTAssertNil(ProjectMeshTaskTitle.presentable("~/dev/nodvox"))
        XCTAssertNil(ProjectMeshTaskTitle.presentable("   \n  "))
        XCTAssertEqual(
            ProjectMeshTaskTitle.text(task("   "), session: nil), L("Untitled chat")
        )
    }
}
