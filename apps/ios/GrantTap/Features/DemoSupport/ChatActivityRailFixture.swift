#if DEBUG
import Foundation

@MainActor
enum ChatActivityRailFixture {
    static func apply(to model: AppModel, at now: Double) {
        let scenario = ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_WORK"]
        guard ["1", "empty", "loading"].contains(scenario) else { return }
        if scenario != "1" {
            applyEmptyWorkspace(to: model, at: now, hidesFolder: scenario == "empty")
            return
        }
        let sessionId = AppModelDemoFixtures.codexSessionId
        let names = ["Sources/AppModel.swift", "Sources/GraphView.swift", "README.md", "Tests/GraphTests.swift"]
        let added = [120, 80, 27, 20], removed = [25, 40, 13, 30]
        let files = names.enumerated().map { index, path in
            RecordedFileChange(path: path, linesAdded: added[index], linesRemoved: removed[index],
                               diff: "@@ -1 +1 @@\n-old value\n+new value \(index)\n")
        }
        let old = RecordedFileChange(path: "old-file.swift", linesAdded: 100, linesRemoved: 100, diff: "+old")
        let entries = [
            ActivityEntry(id: "work-old-user", kind: "user", text: "Previous reply", createdAt: now - 10),
            ActivityEntry(id: "work-old-final", kind: "final", text: "Old changes", createdAt: now - 9,
                          fileChanges: [old]),
            ActivityEntry(id: "work-user", kind: "user", text: "Review this reply's work", createdAt: now - 8),
            ActivityEntry(id: "work-tool", kind: "tool", text: "Saved edits", createdAt: now - 7,
                          fileChanges: files),
            ActivityEntry(id: "work-final", kind: "final", text: "Four files updated", createdAt: now - 6,
                          fileChanges: files),
            ActivityEntry(id: "work-child-review", kind: "message", text: "Reviewed the component connections.",
                          createdAt: now - 5, childThreadId: "demo-agent-release", childThreadDepth: 1),
        ]
        model.activities[sessionId] = SessionActivity(sessionId: sessionId, agent: "codex", state: "idle",
            entries: entries, generatedAt: now, history: .init(hasMore: false))
        model.pending = []
        model.questions = []
        let scope = model.imageStorageScope(sessionId)
        let root = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
            requestId: "workspace-demo-root", path: "", entries: [
                .init(path: "Sources", name: "Sources", kind: "directory"),
                .init(path: "README.md", name: "README.md", kind: "file", size: 64),
                .init(path: "Tests", name: "Tests", kind: "directory"),
            ], truncated: true, nextOffset: 3, createdAt: now)
        TaskWorkspaceStore.shared.save(root, scope: scope, mode: "directory", offset: 0)
        let extra = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
            requestId: "workspace-demo-more", path: "", entries: [
                .init(path: "LICENSE", name: "LICENSE", kind: "file", size: 20),
            ], truncated: false, createdAt: now)
        TaskWorkspaceStore.shared.save(extra, scope: scope, mode: "directory", offset: 3)
        let sources = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
            requestId: "workspace-demo-sources", path: "Sources", entries: [
                .init(path: "Sources/GraphView.swift", name: "GraphView.swift", kind: "file", size: 60),
            ], truncated: false, createdAt: now)
        TaskWorkspaceStore.shared.save(sources, scope: scope, mode: "directory", offset: 0)
        let text = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
            requestId: "workspace-demo-text", path: "Sources/GraphView.swift", text: "let phase = \"ready\"\n",
            truncated: true, nextOffset: 20, createdAt: now)
        TaskWorkspaceStore.shared.save(text, scope: scope, mode: "file", offset: 0)
        let remainder = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
            requestId: "workspace-demo-remainder", path: "Sources/GraphView.swift", text: "// cached remainder\n",
            truncated: false, createdAt: now)
        TaskWorkspaceStore.shared.save(remainder, scope: scope, mode: "file", offset: 20)
        for path in ["README.md", "LICENSE"] {
            let preview = TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: sessionId,
                requestId: "workspace-demo-complete-\(path)", path: path,
                text: "# GrantTap\nFixture file for reviewing edits.\n", truncated: false, createdAt: now)
            TaskWorkspaceStore.shared.save(preview, scope: scope, mode: "file", offset: 0)
        }
    }

    private static func applyEmptyWorkspace(to model: AppModel, at now: Double, hidesFolder: Bool) {
        let sessionId = AppModelDemoFixtures.codexSessionId
        if hidesFolder, let index = model.sessions.firstIndex(where: { $0.sessionId == sessionId }) {
            model.sessions[index].cwd = nil
        }
        model.activities[sessionId] = SessionActivity(sessionId: sessionId, agent: "codex", state: "idle",
            entries: [ActivityEntry(id: "no-changes", kind: "message", text: "No edits in this reply.",
                                    createdAt: now)], generatedAt: now, history: .init(hasMore: false))
        model.pending = []
        model.questions = []
    }
}
#endif
