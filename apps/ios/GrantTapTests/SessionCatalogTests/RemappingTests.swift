import XCTest
@testable import GrantTap

extension SessionCatalogTests {
    func testRemappingLocalSessionRootUpdatesOnlyDirectChildParents() {
        let direct = ChildThreadInfo(
            threadId: "child",
            parentThreadId: "old-root",
            title: "Direct",
            depth: 1,
            state: "idle",
            startedAt: 10,
            lastActivityAt: 20,
            tokensSession: 30,
            tokensLastTurn: 40
        )
        let grandchild = ChildThreadInfo(
            threadId: "grandchild",
            parentThreadId: "child",
            title: "Nested",
            depth: 2,
            state: "working",
            startedAt: 50,
            lastActivityAt: 60,
            tokensSession: 70,
            tokensLastTurn: 80
        )
        let source = SessionInfo(
            sessionId: "old-root",
            agent: "codex",
            title: "Root",
            cwd: "/repo",
            state: "working",
            startedAt: 1,
            lastActivityAt: 2,
            tokensSession: 3,
            tokensLastTurn: 4,
            childThreads: [direct, grandchild],
            shellAllowed: false
        )

        let remapped = source.remappingLocalSessionRoot(to: "new-root")

        XCTAssertEqual(remapped.sessionId, "new-root")
        XCTAssertEqual(remapped.childThreads?.map(\.threadId), ["child", "grandchild"])
        XCTAssertEqual(remapped.childThreads?.map(\.parentThreadId), ["new-root", "child"])
        XCTAssertEqual(remapped.shellAllowed, false)
    }

    func testReplacingLocalSessionValuesPreservesEveryUnchangedField() {
        let child = ChildThreadInfo(
            threadId: "child",
            parentThreadId: "old-session",
            title: "Investigate",
            agentName: "researcher",
            depth: 1,
            state: "waiting",
            startedAt: 101,
            lastActivityAt: 202,
            tokensSession: 303,
            tokensLastTurn: 404
        )
        let server = McpServerInfo(
            name: "github",
            configuredEnabled: true,
            allowed: false,
            authStatus: "connected",
            title: "GitHub",
            websiteUrl: "https://github.com",
            version: "1.2.3",
            icons: [McpIconInfo(
                src: "https://github.com/icon.png",
                mimeType: "image/png",
                sizes: ["64x64"],
                theme: "dark",
                sourceOrigin: "manifest"
            )],
            metadataSource: "bridge"
        )
        let skill = SkillInfo(name: "review", description: "Review code", allowed: false)
        let source = SessionInfo(
            sessionId: "old-session",
            agent: "codex",
            title: "Original title",
            cwd: "/repo/original",
            branch: "feature/session-copy",
            model: "gpt-5",
            summary: "Original summary",
            accessLevel: "workspace-write",
            state: "idle",
            startedAt: 11,
            lastActivityAt: 22,
            tokensSession: 33,
            tokensLastTurn: 44,
            contextTokensUsed: 55,
            contextWindow: 66,
            mcpServers: [server],
            skills: [skill],
            childThreads: [child],
            shellAllowed: false
        )

        let actual = source.replacingLocalSessionValues(
            sessionId: "new-session",
            title: "Updated title",
            cwd: "/repo/updated",
            state: "working",
            lastActivityAt: 99
        )

        XCTAssertEqual(actual, SessionInfo(
            sessionId: "new-session",
            agent: "codex",
            title: "Updated title",
            cwd: "/repo/updated",
            branch: "feature/session-copy",
            model: "gpt-5",
            summary: "Original summary",
            accessLevel: "workspace-write",
            state: "working",
            startedAt: 11,
            lastActivityAt: 99,
            tokensSession: 33,
            tokensLastTurn: 44,
            contextTokensUsed: 55,
            contextWindow: 66,
            mcpServers: [server],
            skills: [skill],
            childThreads: [child],
            shellAllowed: false
        ))
    }
}
